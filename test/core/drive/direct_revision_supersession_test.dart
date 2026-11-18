import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_audit_repository.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:firecheck/core/drive/fake_drive_upload_api.dart';
import 'package:firecheck/core/drive/finalize_assignment_upload_use_case.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ignore: subtype_of_sealed_class
class _NoRemote implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('No remote calls allowed');
}

class _Audit extends DriveUploadAuditRepository {
  _Audit() : super(_NoRemote());
  final counts = <int>[];

  @override
  Future<void> record({
    required String assignmentId,
    required String uploadedBy,
    required String driveFolderPath,
    required String driveFolderUrl,
    required int fileCount,
  }) async =>
      counts.add(fileCount);
}

/// Models the direct adapter's stable same-name component updates.
class _StableDrive extends FakeDriveUploadApi {
  final bytes = <String, List<int>>{};
  bool failDbf = false;
  int attempts = 0;
  Completer<void>? uploadEntered;
  Completer<void>? resumeUpload;

  @override
  Future<String> uploadFile({
    required String localPath,
    required String driveParentId,
    required String fileName,
    String? resumableUri,
    void Function(int sent, int total)? onProgress,
  }) async {
    attempts++;
    if (attempts == 1 && uploadEntered != null) {
      uploadEntered!.complete();
      await resumeUpload!.future;
    }
    if (failDbf && fileName.endsWith('.dbf')) throw Exception('network');
    bytes[fileName] = await File(localPath).readAsBytes();
    uploadedPaths.add(localPath);
    return 'stable-$fileName';
  }
}

class _PausedSelectionRepository extends DriveUploadRepository {
  _PausedSelectionRepository(super.db);
  final selected = Completer<void>();
  final resume = Completer<void>();

  @override
  Future<List<DriveUploadJob>> getPendingJobs({
    DateTime? now,
    int? limit,
    String? ownerId,
  }) async {
    final jobs =
        await super.getPendingJobs(now: now, limit: limit, ownerId: ownerId);
    if (!selected.isCompleted) {
      selected.complete();
      await resume.future;
    }
    return jobs;
  }
}

void main() {
  late AppDatabase db;
  late DriveUploadRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DriveUploadRepository(db);
  });
  tearDown(() => db.close());

  Future<void> seed(
    String id, {
    String? batch = 'A',
    String? owner = 'user',
    String assignment = 'map',
    String type = DriveFileType.shapefile,
    String status = DriveUploadJobStatus.pending,
    String? path,
    String name = 'buildings.shp',
  }) async {
    await repo.insertJob(
      id: id,
      assignmentId: assignment,
      ownerId: owner,
      batchId: batch,
      filePath: path ?? '/$id',
      fileType: type,
      fileName: name,
      fileSizeBytes: 1,
      capturedAt: DateTime(2026),
    );
    // All timestamps tie; lexical IDs deliberately disagree with insertion.
    await db.customStatement(
      'UPDATE drive_upload_jobs SET created_at = 1 WHERE id = ?',
      [id],
    );
    switch (status) {
      case DriveUploadJobStatus.dead:
        await repo.markDead(id, reason: 'exhausted');
      case DriveUploadJobStatus.completed:
        await repo.markCompleted(id, driveFileId: 'stable-$name');
      case DriveUploadJobStatus.uploading:
        await repo.markUploading(id);
      case DriveUploadJobStatus.failed:
        await repo.markFailed(
          id,
          reason: 'network',
          retryCount: 1,
          nextRetryAt: DateTime(2020),
        );
    }
  }

  Future<String> status(String id) async =>
      (await repo.getJobsForAssignment('map'))
          .firstWhere((j) => j.id == id)
          .status;

  for (final accepted in [
    DriveUploadJobStatus.completed,
    DriveUploadJobStatus.uploading,
  ]) {
    for (final resetAll in [false, true]) {
      test(
          'retry cannot revive old batch after newer $accepted (all=$resetAll)',
          () async {
        await seed('z-old-shp', status: DriveUploadJobStatus.dead);
        await seed(
          'z-old-dbf',
          status: DriveUploadJobStatus.dead,
          name: 'buildings.dbf',
        );
        await seed('a-new-shp', batch: 'B', status: accepted);
        await seed(
          'a-new-dbf',
          batch: 'B',
          status: DriveUploadJobStatus.dead,
          name: 'buildings.dbf',
        );
        if (resetAll) {
          await repo.resetFailedToPending(ownerId: 'user');
        } else {
          await repo.resetForRetry('z-old-shp', ownerId: 'user');
          await repo.resetForRetry('z-old-dbf', ownerId: 'user');
        }
        expect(await status('z-old-shp'), DriveUploadJobStatus.dead);
        expect(await status('z-old-dbf'), DriveUploadJobStatus.dead);
        expect(await repo.getJobsForAssignment('map'), hasLength(4));
      });
    }
  }

  test('claim rejects externally revived batch once newer component accepted',
      () async {
    await seed('z-old', status: DriveUploadJobStatus.dead);
    await seed('a-new', batch: 'B', status: DriveUploadJobStatus.completed);
    await db.customStatement(
      "UPDATE drive_upload_jobs SET status='pending' WHERE id='z-old'",
    );
    expect(await repo.getPendingJobs(ownerId: 'user'), isEmpty);
  });

  test('stale old pending rows do not block remaining newer components',
      () async {
    await seed('z-old', status: DriveUploadJobStatus.dead);
    await seed('a-new-shp', batch: 'B', status: DriveUploadJobStatus.completed);
    await seed(
      'a-new-dbf',
      batch: 'B',
      status: DriveUploadJobStatus.failed,
      name: 'buildings.dbf',
    );
    await db.customStatement(
      "UPDATE drive_upload_jobs SET status='pending' WHERE id='z-old'",
    );
    expect(
      (await repo.getPendingJobs(ownerId: 'user')).map((job) => job.id),
      ['a-new-dbf'],
    );
  });

  test('late old component cannot supersede newer batch or reverse its order',
      () async {
    await seed('z-old-first', status: DriveUploadJobStatus.dead);
    await seed('a-new', batch: 'B', status: DriveUploadJobStatus.completed);
    await seed(
      'z-old-last',
      status: DriveUploadJobStatus.dead,
      name: 'buildings.dbf',
    );
    await repo.resetFailedToPending(ownerId: 'user');
    expect(await status('z-old-last'), DriveUploadJobStatus.dead);
    expect(await repo.getPendingJobs(ownerId: 'user'), isEmpty);
  });

  test('null-owner legacy batches remain scoped independently', () async {
    await seed(
      'legacy-old',
      owner: null,
      batch: null,
      status: DriveUploadJobStatus.dead,
    );
    await seed('owned-new', batch: 'B', status: DriveUploadJobStatus.completed);
    await repo.resetForRetry('legacy-old');
    expect(await status('legacy-old'), DriveUploadJobStatus.pending);
    await repo.markDead('legacy-old', reason: 'exhausted');
    await seed(
      'legacy-new',
      owner: null,
      batch: 'C',
      status: DriveUploadJobStatus.completed,
    );
    await repo.resetFailedToPending();
    expect(await status('legacy-old'), DriveUploadJobStatus.dead);
  });

  test('pending newer batch preserves FIFO and same-operation retry', () async {
    await seed('z-old', status: DriveUploadJobStatus.dead);
    await seed('a-new', batch: 'B');
    await repo.resetForRetry('z-old', ownerId: 'user');
    expect(
      (await repo.getPendingJobs(ownerId: 'user')).map((j) => j.id),
      ['z-old'],
    );
    await repo.markCompleted('z-old', driveFileId: 'stable');
    expect(
      (await repo.getPendingJobs(ownerId: 'user')).map((j) => j.id),
      ['a-new'],
    );
  });

  test('supersession stays scoped to account, map, shapefiles and batch',
      () async {
    await seed('retry', status: DriveUploadJobStatus.dead);
    await seed('same-batch', status: DriveUploadJobStatus.completed);
    await seed(
      'other-owner',
      owner: 'other',
      batch: 'B',
      status: DriveUploadJobStatus.completed,
    );
    await seed(
      'other-map',
      assignment: 'other',
      batch: 'B',
      status: DriveUploadJobStatus.completed,
    );
    await seed(
      'photo',
      type: DriveFileType.photo,
      batch: 'B',
      status: DriveUploadJobStatus.dead,
    );
    await repo.resetForRetry('retry', ownerId: 'other');
    expect(await status('retry'), DriveUploadJobStatus.dead);
    await repo.resetFailedToPending(ownerId: 'user');
    expect(
      (await repo.getPendingJobs(ownerId: 'user')).map((j) => j.id),
      containsAll(['retry', 'photo']),
    );
  });

  for (final partiallyWritten in [false, true]) {
    test('worker keeps stable newer bytes (partial=$partiallyWritten)',
        () async {
      final dir = await Directory.systemTemp.createTemp('superseded-drive-');
      addTearDown(() => dir.delete(recursive: true));
      await db.into(db.assignments).insert(
            AssignmentsCompanion.insert(
              id: 'map',
              enumeratorId: 'user',
              campaignId: 'campaign',
              boundaryPolygonGeojson: '{}',
              createdAt: DateTime(2026),
            ),
          );
      for (final batch in ['A', 'B']) {
        for (final extension in ['shp', 'dbf', 'shx', 'prj']) {
          final path = '${dir.path}/$batch.$extension';
          await File(path).writeAsBytes([if (batch == 'A') 1 else 2]);
          await seed(
            '$batch-$extension',
            batch: batch,
            path: path,
            name: 'buildings.$extension',
            status: batch == 'A'
                ? DriveUploadJobStatus.dead
                : DriveUploadJobStatus.pending,
          );
        }
      }
      final api = _StableDrive()..failDbf = partiallyWritten;
      final worker = DriveUploadWorker(
        api: api,
        repo: repo,
        db: db,
        currentUserId: () => 'user',
        enumeratorIdentifier: () => 'user@example.com',
      );
      await worker.drain();
      expect(api.bytes, hasLength(partiallyWritten ? 3 : 4));
      expect(api.bytes.values, everyElement([2]));
      api.failDbf = false;
      await repo.resetForRetry('A-shp', ownerId: 'user');
      await repo.resetFailedToPending(ownerId: 'user');
      // A stale caller can still have revived a row outside the reset methods.
      await db.customStatement(
        "UPDATE drive_upload_jobs SET status='pending' WHERE id='A-dbf'",
      );
      await worker.drain();
      expect(api.uploadedPaths, hasLength(4));
      expect(api.bytes, hasLength(4));
      expect(api.bytes.values, everyElement([2]));
    });
  }

  Future<void> seedWorkerFiles(Directory dir) async {
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'map',
            enumeratorId: 'user',
            campaignId: 'campaign',
            boundaryPolygonGeojson: '{}',
            createdAt: DateTime(2026),
          ),
        );
    for (final revision in ['A', 'B']) {
      final path = '${dir.path}/$revision.shp';
      await File(path).writeAsBytes([if (revision == 'A') 1 else 2]);
      await seed(
        revision,
        batch: revision,
        path: path,
        status: revision == 'A'
            ? DriveUploadJobStatus.dead
            : DriveUploadJobStatus.pending,
      );
    }
  }

  DriveUploadWorker concurrentWorker(
    DriveUploadRepository repository,
    _StableDrive api,
  ) =>
      DriveUploadWorker(
        api: api,
        repo: repository,
        db: db,
        currentUserId: () => 'user',
        enumeratorIdentifier: () => 'user',
      );

  test('two workers cannot replay stale A selection after B writes', () async {
    final dir = await Directory.systemTemp.createTemp('drive-interleave-');
    addTearDown(() => dir.delete(recursive: true));
    await db.close();
    final databaseFile = File('${dir.path}/uploads.sqlite');
    db = AppDatabase.forTesting(NativeDatabase(databaseFile));
    repo = DriveUploadRepository(db);
    await seedWorkerFiles(dir);
    final otherConnection =
        AppDatabase.forTesting(NativeDatabase(databaseFile));
    addTearDown(otherConnection.close);
    final selectedB = _PausedSelectionRepository(db);
    final selectedA = _PausedSelectionRepository(otherConnection);
    final api = _StableDrive();
    final bDrain = concurrentWorker(selectedB, api).drain();
    await selectedB.selected.future;
    await repo.resetForRetry('A', ownerId: 'user');
    final aDrain = concurrentWorker(selectedA, api).drain();
    await selectedA.selected.future;
    selectedB.resume.complete();
    await bDrain;
    selectedA.resume.complete();
    await aDrain;
    expect(api.bytes['buildings.shp'], [2]);
    expect(api.uploadedPaths, hasLength(2));
  });

  test('a second drain cannot recover a possibly live upload', () async {
    final dir = await Directory.systemTemp.createTemp('drive-live-');
    addTearDown(() => dir.delete(recursive: true));
    await seedWorkerFiles(dir);
    final api = _StableDrive()
      ..uploadEntered = Completer<void>()
      ..resumeUpload = Completer<void>();
    final first = concurrentWorker(repo, api).drain();
    await api.uploadEntered!.future;
    await concurrentWorker(DriveUploadRepository(db), api).drain();
    api.resumeUpload!.complete();
    await first;
    expect(api.attempts, 1);
  });

  test('individual retry never steals an uploading job', () async {
    await seed('active', status: DriveUploadJobStatus.uploading);
    await repo.resetForRetry('active', ownerId: 'user');
    await repo.resetFailedToPending(ownerId: 'user');
    expect(await status('active'), DriveUploadJobStatus.uploading);
  });

  test('prior VM claims recover only for the original account', () async {
    final dir = await Directory.systemTemp.createTemp('drive-recover-');
    addTearDown(() => dir.delete(recursive: true));
    await seedWorkerFiles(dir);
    expect(
      await repo.claimForUpload(
        'B',
        ownerId: 'user',
        processIdentity: 'prior-vm',
      ),
      isTrue,
    );
    final api = _StableDrive();
    await DriveUploadWorker(
      api: api,
      repo: repo,
      db: db,
      currentUserId: () => 'other',
      enumeratorIdentifier: () => 'other',
      processIdentity: () async => 'new-vm',
    ).drain();
    expect(await status('B'), DriveUploadJobStatus.uploading);
    await DriveUploadWorker(
      api: api,
      repo: repo,
      db: db,
      currentUserId: () => 'user',
      enumeratorIdentifier: () => 'user',
      processIdentity: () async => 'new-vm',
    ).drain();
    expect(await status('B'), DriveUploadJobStatus.completed);
    expect(api.bytes['buildings.shp'], [2]);
  });

  test('missing process identity neither recovers nor uploads', () async {
    final dir = await Directory.systemTemp.createTemp('drive-no-identity-');
    addTearDown(() => dir.delete(recursive: true));
    await seedWorkerFiles(dir);
    expect(
      await repo.claimForUpload(
        'B',
        ownerId: 'user',
        processIdentity: 'possibly-live-vm',
      ),
      isTrue,
    );
    final api = _StableDrive();
    await DriveUploadWorker(
      api: api,
      repo: repo,
      db: db,
      currentUserId: () => 'user',
      enumeratorIdentifier: () => 'user',
      processIdentity: () async => null,
    ).drain();
    expect(await status('B'), DriveUploadJobStatus.uploading);
    expect(api.attempts, 0);
    expect(api.uploadedPaths, isEmpty);
  });

  for (final latestStatus in [
    DriveUploadJobStatus.completed,
    DriveUploadJobStatus.pending,
  ]) {
    test('direct finalizer uses latest intended batch ($latestStatus)',
        () async {
      await db.into(db.assignments).insert(
            AssignmentsCompanion.insert(
              id: 'map',
              enumeratorId: 'user',
              campaignId: 'campaign',
              boundaryPolygonGeojson: '{}',
              createdAt: DateTime(2026),
            ),
          );
      await seed(
        'z-old',
        status: latestStatus == DriveUploadJobStatus.completed
            ? DriveUploadJobStatus.dead
            : DriveUploadJobStatus.completed,
      );
      await seed('a-new', batch: 'B', status: latestStatus);
      await seed(
        'late-old-component',
        status: latestStatus == DriveUploadJobStatus.completed
            ? DriveUploadJobStatus.dead
            : DriveUploadJobStatus.completed,
        name: 'buildings.dbf',
      );
      await seed(
        'media',
        type: DriveFileType.photo,
        status: DriveUploadJobStatus.completed,
      );
      final audit = _Audit();
      final finalizer = FinalizeAssignmentUploadUseCase(
        db: db,
        repo: repo,
        assignmentRepo: AssignmentRepository(db: db),
        auditRepo: audit,
        currentUserId: () => 'user',
        now: () => DateTime(2026, 11, 18),
      );
      final result =
          await finalizer.execute(assignmentId: 'map', uploaderId: 'user');
      if (latestStatus == DriveUploadJobStatus.completed) {
        expect(result, isA<DriveUploadSucceeded>());
        expect((result as DriveUploadSucceeded).completedCount, 2);
        expect(audit.counts, [2]);
        expect(
          (await db.select(db.assignments).getSingle()).driveUploadConfirmedAt,
          DateTime(2026, 11, 18),
        );
      } else {
        expect(result, isA<DriveUploadIncomplete>());
        expect(audit.counts, isEmpty);
        expect(
          (await db.select(db.assignments).getSingle()).driveUploadConfirmedAt,
          isNull,
        );
      }
    });
  }
  test(
      'direct finalizer preserves media-only completion and pending media gate',
      () async {
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'map',
            enumeratorId: 'user',
            campaignId: 'campaign',
            boundaryPolygonGeojson: '{}',
            createdAt: DateTime(2026),
          ),
        );
    await seed(
      'photo-only',
      type: DriveFileType.photo,
      batch: null,
      status: DriveUploadJobStatus.completed,
    );
    final audit = _Audit();
    final finalizer = FinalizeAssignmentUploadUseCase(
      db: db,
      repo: repo,
      assignmentRepo: AssignmentRepository(db: db),
      auditRepo: audit,
    );
    expect(
      await finalizer.execute(assignmentId: 'map', uploaderId: 'user'),
      isA<DriveUploadSucceeded>(),
    );
    await seed('pending-photo', type: DriveFileType.photo, batch: 'B');
    expect(
      await finalizer.execute(assignmentId: 'map', uploaderId: 'user'),
      isA<DriveUploadIncomplete>(),
    );
    expect(audit.counts, [1]);
  });
}
