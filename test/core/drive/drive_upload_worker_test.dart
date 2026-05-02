import 'dart:io';
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:firecheck/core/drive/fake_drive_upload_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('worker_test_');
  });
  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<String> _seedPhoto(AppDatabase db, DriveUploadRepository repo, String id) async {
    final path = '${tempDir.path}/$id.jpg';
    await File(path).writeAsBytes([0xFF, 0xD8]);
    await repo.insertJob(
      id: id, assignmentId: 'a1', filePath: path,
      fileType: DriveFileType.photo, fileName: '$id.jpg',
      fileSizeBytes: 2, capturedAt: DateTime(2026),
    );
    return path;
  }

  // Seed the assignment row so _resolveParentFolder can find it
  Future<void> _seedAssignment(AppDatabase db) async {
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
      id: 'a1', enumeratorId: 'e1', campaignId: 'c1',
      boundaryPolygonGeojson: '{}', createdAt: DateTime(2026),
    ));
  }

  test('drain marks job completed on successful upload', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriveUploadRepository(db);
    final api = FakeDriveUploadApi();
    await _seedAssignment(db);
    await _seedPhoto(db, repo, 'j1');

    final worker = DriveUploadWorker(
      api: api,
      repo: repo,
      db: db,
      rootFolderId: 'root-folder',
    );
    await worker.drain();

    final jobs = await db.select(db.driveUploadJobs).get();
    expect(jobs.first.status, DriveUploadJobStatus.completed);
    expect(jobs.first.driveFileId, isNotNull);
    expect(api.uploadedPaths.length, 1);
  });

  test('drain marks job failed on transient error (retryCount increments)', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriveUploadRepository(db);
    final api = FakeDriveUploadApi(throwOnUpload: true);
    await _seedAssignment(db);
    await _seedPhoto(db, repo, 'j1');

    final worker = DriveUploadWorker(
      api: api,
      repo: repo,
      db: db,
      rootFolderId: 'root-folder',
    );
    await worker.drain();

    final jobs = await db.select(db.driveUploadJobs).get();
    expect(jobs.first.status, DriveUploadJobStatus.failed);
    expect(jobs.first.retryCount, 1);
    expect(jobs.first.nextRetryAt, isNotNull);
  });

  test('drain marks job dead after 3 failures', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriveUploadRepository(db);
    final api = FakeDriveUploadApi(throwOnUpload: true);
    await _seedAssignment(db);
    await _seedPhoto(db, repo, 'j1');

    final worker = DriveUploadWorker(
      api: api,
      repo: repo,
      db: db,
      rootFolderId: 'root-folder',
    );

    // Drain 3× with retry time set to past each time
    for (var i = 0; i < 3; i++) {
      // Reset nextRetryAt to past so it's eligible
      await db.customStatement(
        'UPDATE drive_upload_jobs SET next_retry_at = NULL WHERE id = ?',
        ['j1'],
      );
      await worker.drain();
    }

    final jobs = await db.select(db.driveUploadJobs).get();
    expect(jobs.first.status, DriveUploadJobStatus.dead);
  });

  test('drain skips job whose local file is missing', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriveUploadRepository(db);
    final api = FakeDriveUploadApi();
    await _seedAssignment(db);
    await repo.insertJob(
      id: 'j1', assignmentId: 'a1',
      filePath: '/nonexistent/missing.jpg',
      fileType: DriveFileType.photo, fileName: 'missing.jpg',
      fileSizeBytes: 0, capturedAt: DateTime(2026),
    );

    final worker = DriveUploadWorker(
      api: api,
      repo: repo,
      db: db,
      rootFolderId: 'root-folder',
    );
    await worker.drain();

    final jobs = await db.select(db.driveUploadJobs).get();
    expect(jobs.first.status, DriveUploadJobStatus.dead);
    expect(jobs.first.failureReason, contains('missing'));
    expect(api.uploadedPaths, isEmpty);
  });
}
