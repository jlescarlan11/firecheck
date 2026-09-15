import 'dart:io';

import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:firecheck/core/drive/fake_drive_upload_api.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingRepository extends DriveUploadRepository {
  _RecordingRepository(super.db);
  final batchSizes = <int>[];

  @override
  Future<List<DriveUploadJob>> getPendingJobs({
    DateTime? now,
    int? limit,
  }) async {
    final jobs = await super.getPendingJobs(now: now, limit: limit);
    batchSizes.add(jobs.length);
    return jobs;
  }
}

void main() {
  late AppDatabase db;
  late _RecordingRepository repo;
  late Directory directory;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = _RecordingRepository(db);
    directory = await Directory.systemTemp.createTemp('upload_batch_');
    for (var i = 0; i < 7; i++) {
      final path = '${directory.path}/$i.jpg';
      await File(path).writeAsBytes([0xFF, 0xD8]);
      await repo.insertJob(
        id: 'job-$i',
        assignmentId: 'assignment',
        filePath: path,
        fileType: DriveFileType.photo,
        fileName: '$i.jpg',
        fileSizeBytes: 2,
        capturedAt: DateTime(2026),
      );
    }
    // Exercise deterministic ordering when timestamps tie.
    await db.customStatement('UPDATE drive_upload_jobs SET created_at = 0');
  });

  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  test('SQL limit follows eligibility filtering and stable order', () async {
    final now = DateTime(2026, 9, 15);
    await repo.markCompleted('job-0', driveFileId: 'uploaded');
    await repo.markFailed(
      'job-1',
      reason: 'retry later',
      retryCount: 1,
      nextRetryAt: now.add(const Duration(hours: 1)),
    );
    final jobs = await repo.getPendingJobs(now: now, limit: 3);
    expect(jobs.map((job) => job.id), ['job-2', 'job-3', 'job-4']);
    expect(await repo.getPendingJobs(now: now), hasLength(5));
  });

  test('worker drains all jobs while loading only one batch at a time',
      () async {
    final api = FakeDriveUploadApi();
    final worker = DriveUploadWorker(
      api: api,
      repo: repo,
      db: db,
      enumeratorIdentifier: () => 'test@example.com',
    );
    await worker.drain();
    expect(repo.batchSizes, [3, 3, 1, 0]);
    expect(api.uploadedPaths, hasLength(7));
    final jobs = await db.select(db.driveUploadJobs).get();
    expect(
      jobs.every((job) => job.status == DriveUploadJobStatus.completed),
      isTrue,
    );
  });

  test('nonpositive limits fail instead of silently leaving work pending', () {
    expect(repo.getPendingJobs(limit: 0), throwsArgumentError);
    expect(repo.getPendingJobs(limit: -1), throwsArgumentError);
  });
}
