import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  group('DriveUploadRepository', () {
    test('insertJob creates a pending job', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);

      await repo.insertJob(
        id: 'j1',
        assignmentId: 'a1',
        filePath: '/photos/p1.jpg',
        fileType: DriveFileType.photo,
        fileName: 'p1.jpg',
        fileSizeBytes: 1024,
        capturedAt: DateTime(2026, 5, 2),
      );

      final jobs = await repo.getPendingJobs();
      expect(jobs.length, 1);
      expect(jobs.first.status, DriveUploadJobStatus.pending);
    });

    test('getPendingJobs excludes completed and future-retry jobs', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);

      await repo.insertJob(id: 'j1', assignmentId: 'a1', filePath: '/p1.jpg',
          fileType: DriveFileType.photo, fileName: 'p1.jpg',
          fileSizeBytes: 100, capturedAt: DateTime(2026));
      await repo.insertJob(id: 'j2', assignmentId: 'a1', filePath: '/p2.jpg',
          fileType: DriveFileType.photo, fileName: 'p2.jpg',
          fileSizeBytes: 100, capturedAt: DateTime(2026));

      await repo.markCompleted('j1', driveFileId: 'drive-1');
      await repo.markFailed('j2',
          reason: 'network', retryCount: 1,
          nextRetryAt: DateTime.now().add(const Duration(hours: 1)));

      final jobs = await repo.getPendingJobs();
      expect(jobs, isEmpty);
    });

    test('getPendingJobs includes failed jobs whose retry time has passed', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);

      await repo.insertJob(id: 'j1', assignmentId: 'a1', filePath: '/p1.jpg',
          fileType: DriveFileType.photo, fileName: 'p1.jpg',
          fileSizeBytes: 100, capturedAt: DateTime(2026));
      await repo.markFailed('j1',
          reason: 'err', retryCount: 1,
          nextRetryAt: DateTime.now().subtract(const Duration(seconds: 1)));

      final jobs = await repo.getPendingJobs();
      expect(jobs.length, 1);
    });

    test('markDead sets status=dead and failureReason', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);

      await repo.insertJob(id: 'j1', assignmentId: 'a1', filePath: '/p1.jpg',
          fileType: DriveFileType.photo, fileName: 'p1.jpg',
          fileSizeBytes: 100, capturedAt: DateTime(2026));
      await repo.markDead('j1', reason: 'file missing');

      final all = await db.select(db.driveUploadJobs).get();
      expect(all.first.status, DriveUploadJobStatus.dead);
      expect(all.first.failureReason, 'file missing');
    });

    test('resetForRetry resets retryCount and status to pending', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);

      await repo.insertJob(id: 'j1', assignmentId: 'a1', filePath: '/p1.jpg',
          fileType: DriveFileType.photo, fileName: 'p1.jpg',
          fileSizeBytes: 100, capturedAt: DateTime(2026));
      await repo.markDead('j1', reason: 'err');
      await repo.resetForRetry('j1');

      final all = await db.select(db.driveUploadJobs).get();
      expect(all.first.status, DriveUploadJobStatus.pending);
      expect(all.first.retryCount, 0);
      expect(all.first.failureReason, isNull);
      expect(all.first.nextRetryAt, isNull);
    });

    test('resetFailedToPending resets failed jobs only, not dead', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);

      await repo.insertJob(id: 'j1', assignmentId: 'a1', filePath: '/p1.jpg',
          fileType: DriveFileType.photo, fileName: 'p1.jpg',
          fileSizeBytes: 100, capturedAt: DateTime(2026));
      await repo.insertJob(id: 'j2', assignmentId: 'a1', filePath: '/p2.jpg',
          fileType: DriveFileType.photo, fileName: 'p2.jpg',
          fileSizeBytes: 100, capturedAt: DateTime(2026));

      await repo.markFailed('j1', reason: 'net', retryCount: 1,
          nextRetryAt: DateTime.now().add(const Duration(hours: 1)));
      await repo.markDead('j2', reason: 'perma');

      await repo.resetFailedToPending();

      final all = await db.select(db.driveUploadJobs).get();
      final j1 = all.firstWhere((j) => j.id == 'j1');
      final j2 = all.firstWhere((j) => j.id == 'j2');
      expect(j1.status, DriveUploadJobStatus.pending);
      expect(j2.status, DriveUploadJobStatus.dead); // unchanged
    });

    test('jobExistsForFilePath returns true when non-completed job exists', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);

      await repo.insertJob(id: 'j1', assignmentId: 'a1', filePath: '/p1.jpg',
          fileType: DriveFileType.photo, fileName: 'p1.jpg',
          fileSizeBytes: 100, capturedAt: DateTime(2026));

      expect(await repo.jobExistsForFilePath('/p1.jpg'), isTrue);
      expect(await repo.jobExistsForFilePath('/other.jpg'), isFalse);
    });

    test('shapefileJobExistsForAssignment returns true while a job is in flight', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);

      await repo.insertJob(id: 'j1', assignmentId: 'a1', filePath: '/buildings.shp',
          fileType: DriveFileType.shapefile, fileName: 'buildings.shp',
          fileSizeBytes: 1000, capturedAt: DateTime(2026));

      // Pending → still in flight.
      expect(await repo.shapefileJobExistsForAssignment('a1'), isTrue);
    });

    test('shapefileJobExistsForAssignment returns false once the job is completed', () async {
      // Once the upload finishes, the enumerator may re-export and re-upload —
      // server-side supersede handles attribution conflicts. So a completed
      // job must NOT block a fresh enqueue.
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);

      await repo.insertJob(id: 'j1', assignmentId: 'a1', filePath: '/buildings.shp',
          fileType: DriveFileType.shapefile, fileName: 'buildings.shp',
          fileSizeBytes: 1000, capturedAt: DateTime(2026));
      await repo.markCompleted('j1', driveFileId: 'drive-1');

      expect(await repo.shapefileJobExistsForAssignment('a1'), isFalse);
    });

    test('shapefileJobExistsForAssignment returns false when the job is failed (re-enqueue should not be blocked)', () async {
      // Failed jobs are retried by the worker, but every fresh enqueue
      // writes new files in a timestamped subdir — blocking on a stale
      // failed job would force the user to wait for retries against
      // file paths that no longer exist.
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);

      await repo.insertJob(id: 'j1', assignmentId: 'a1', filePath: '/buildings.shp',
          fileType: DriveFileType.shapefile, fileName: 'buildings.shp',
          fileSizeBytes: 1000, capturedAt: DateTime(2026));
      await repo.markFailed('j1',
          reason: '403', retryCount: 1,
          nextRetryAt: DateTime(2026, 5, 20, 11, 30));

      expect(await repo.shapefileJobExistsForAssignment('a1'), isFalse);
    });

    test('shapefileJobExistsForAssignment returns false once the job is dead', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);

      await repo.insertJob(id: 'j1', assignmentId: 'a1', filePath: '/buildings.shp',
          fileType: DriveFileType.shapefile, fileName: 'buildings.shp',
          fileSizeBytes: 1000, capturedAt: DateTime(2026));
      await repo.markDead('j1', reason: 'gave up');

      expect(await repo.shapefileJobExistsForAssignment('a1'), isFalse);
    });

    test('markCompleted clears resumableUri', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);

      await repo.insertJob(id: 'j1', assignmentId: 'a1', filePath: '/p1.jpg',
          fileType: DriveFileType.photo, fileName: 'p1.jpg',
          fileSizeBytes: 100, capturedAt: DateTime(2026));
      await repo.setResumableUri('j1', 'https://resumable-uri');
      await repo.markCompleted('j1', driveFileId: 'drive-1');

      final all = await db.select(db.driveUploadJobs).get();
      expect(all.first.resumableUri, isNull);
    });
  });
}
