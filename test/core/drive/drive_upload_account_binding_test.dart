import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:firecheck/core/drive/google_drive_upload_api.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Tokens implements GoogleTokenSource {
  String? actor = 'A';
  int reads = 0;
  Future<void> Function()? beforeToken;
  @override
  Future<bool> isSignedIn() async => actor != null;
  @override
  Future<String> getEnumeratorId() async =>
      actor ?? (throw const AuthFailure('signed out'));
  @override
  Future<String> getAccessToken() async {
    reads++;
    await beforeToken?.call();
    return 'token-$actor';
  }
}

void main() {
  late AppDatabase db;
  late Directory directory;
  late DriveUploadRepository repo;
  late _Tokens tokens;
  late List<String?> authorization;
  late http.Client client;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DriveUploadRepository(db);
    directory = await Directory.systemTemp.createTemp('drive_accounts_');
    tokens = _Tokens();
    authorization = [];
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'map',
            enumeratorId: 'A',
            campaignId: 'c',
            boundaryPolygonGeojson: '{}',
            createdAt: DateTime.utc(2026),
          ),
        );
  });
  tearDown(() async {
    client.close();
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<void> seed(String id, String? owner) async {
    final path = '${directory.path}/$id.shp';
    await File(path).writeAsBytes([1, 2, 3]);
    await repo.insertJob(
      id: id,
      assignmentId: 'map',
      ownerId: owner,
      filePath: path,
      fileType: 'shapefile',
      fileName: '$id.shp',
      fileSizeBytes: 3,
      capturedAt: DateTime.utc(2026),
      batchId: id,
    );
  }

  DriveUploadWorker worker(
    Future<void> Function(http.Request)? onRequest, {
    String? Function()? currentAccount,
  }) {
    client = MockClient((request) async {
      authorization.add(request.headers['authorization']);
      await onRequest?.call(request);
      return http.Response(
        request.method == 'GET'
            ? '{"files":[{"id":"folder"}]}'
            : '{"id":"uploaded"}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    return DriveUploadWorker(
      currentUserId: currentAccount ?? () => tokens.actor,
      api: GoogleDriveUploadApi(googleAuthRepo: tokens, httpClient: client),
      repo: repo,
      db: db,
      enumeratorIdentifier: () => tokens.actor,
    );
  }

  test('B cannot drain A or unowned pending work through the Google adapter',
      () async {
    await seed('A-job', 'A');
    await seed('legacy-job', null);
    await seed('B-job', 'B');
    tokens.actor = 'B';
    await worker(null).drain();
    final jobs = await db.select(db.driveUploadJobs).get();
    expect(jobs.singleWhere((job) => job.id == 'A-job').status, 'pending');
    expect(jobs.singleWhere((job) => job.id == 'legacy-job').status, 'pending');
    expect(jobs.singleWhere((job) => job.id == 'B-job').status, 'completed');
    expect(authorization.toSet(), {'Bearer token-B'});
    expect(tokens.reads, 1);
  });

  test('B recovery leaves A and unowned uploading rows untouched', () async {
    await seed('A-job', 'A');
    await seed('legacy-job', null);
    await repo.markUploading('A-job');
    await repo.markUploading('legacy-job');
    tokens.actor = 'B';
    await worker(null).drain();
    expect(
      (await db.select(db.driveUploadJobs).get())
          .every((job) => job.status == 'uploading'),
      isTrue,
    );
    expect(authorization, isEmpty);
  });

  test(
      'B upload-all and individual retry cannot reset another owner failed work',
      () async {
    await seed('A-job', 'A');
    await seed('legacy-job', null);
    await seed('B-job', 'B');
    for (final id in ['A-job', 'legacy-job', 'B-job']) {
      await repo.markFailed(
        id,
        reason: 'keep error',
        retryCount: 2,
        nextRetryAt: DateTime.utc(2099),
      );
    }
    tokens.actor = 'B';
    final notifier = DriveUploadNotifier(repo: repo, worker: worker(null));
    await notifier.uploadAll();
    await notifier.retryJob('A-job');
    final jobs = await db.select(db.driveUploadJobs).get();
    for (final id in ['A-job', 'legacy-job']) {
      final job = jobs.singleWhere((job) => job.id == id);
      expect(job.status, 'failed');
      expect(job.retryCount, 2);
      expect(job.failureReason, 'keep error');
    }
    expect(jobs.singleWhere((job) => job.id == 'B-job').status, 'completed');
    notifier.dispose();
  });

  test(
      'bound-session rejection stops this drain even if worker actor remains stale',
      () async {
    await seed('A-job', 'A');
    var reportedActor = 'A';
    final entered = Completer<void>();
    final release = Completer<void>();
    final w = worker(
      (request) async {
        if (!entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      },
      currentAccount: () => reportedActor,
    );
    final running = w.drain();
    await entered.future.timeout(const Duration(seconds: 5));
    tokens.actor = 'B';
    release.complete();
    try {
      await expectLater(running.timeout(const Duration(seconds: 5)), completes);
    } finally {
      reportedActor = 'B';
      await running.timeout(const Duration(seconds: 5));
    }
    final job = await db.select(db.driveUploadJobs).getSingle();
    expect(job.status, 'pending');
    expect(job.retryCount, 0);
    expect(authorization, ['Bearer token-A']);
  });

  for (final stage in ['token', 'folder', 'upload', 'signout']) {
    test(
        'account change during $stage await preserves A job and never sends B credentials',
        () async {
      await seed('A-job', 'A');
      final entered = Completer<void>();
      final release = Completer<void>();
      if (stage == 'token') {
        tokens.beforeToken = () async {
          entered.complete();
          await release.future;
        };
      }
      final w = worker((request) async {
        final shouldHold = stage == 'folder' || stage == 'signout'
            ? authorization.length == 1
            : stage == 'upload' && request.method != 'GET';
        if (shouldHold && !entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      });
      final running = w.drain();
      await entered.future.timeout(const Duration(seconds: 5));
      tokens.actor = stage == 'signout' ? null : 'B';
      release.complete();
      await running.timeout(const Duration(seconds: 5));
      final job = await db.select(db.driveUploadJobs).getSingle();
      expect(job.ownerId, 'A');
      expect(job.status, 'pending');
      expect(job.retryCount, 0);
      expect(
        authorization.where((header) => header != 'Bearer token-A'),
        isEmpty,
      );
      expect(tokens.reads, 1);
      if (stage == 'token') expect(authorization, isEmpty);
      if (stage == 'signout') {
        tokens.actor = 'A';
        await w.drain();
        expect(
          (await db.select(db.driveUploadJobs).getSingle()).status,
          'completed',
        );
        expect(tokens.reads, 2);
      }
    });
  }
}
