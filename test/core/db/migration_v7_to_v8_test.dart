// test/core/db/migration_v7_to_v8_test.dart
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schemaVersion is at least 8', () {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(8));
  });

  test('drive_upload_jobs table exists in sqlite_master', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='drive_upload_jobs'",
        )
        .get();
    expect(rows, hasLength(1));
  });

  test('drive_upload_jobs indexes exist', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    final names = rows.map((r) => r.data['name'] as String).toSet();
    expect(names, contains('drive_upload_jobs_status_idx'));
    expect(names, contains('drive_upload_jobs_assignment_idx'));
  });

  test('status defaults to pending and retryCount defaults to 0', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.driveUploadJobs).insert(
          DriveUploadJobsCompanion.insert(
            id: 'j1',
            assignmentId: 'a-001',
            filePath: '/photos/p1.jpg',
            fileType: 'photo',
            fileName: 'p1.jpg',
            fileSizeBytes: 2048,
            capturedAt: DateTime(2026, 5, 2),
            createdAt: DateTime(2026, 5, 2),
          ),
        );
    final row = await (db.select(db.driveUploadJobs)
          ..where((t) => t.id.equals('j1')))
        .getSingle();
    expect(row.status, 'pending');
    expect(row.retryCount, 0);
  });

  test('nullable columns accept null on insert', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.driveUploadJobs).insert(
          DriveUploadJobsCompanion.insert(
            id: 'j2',
            assignmentId: 'a-001',
            filePath: '/shapefiles/s1.zip',
            fileType: 'shapefile',
            fileName: 's1.zip',
            fileSizeBytes: 8192,
            capturedAt: DateTime(2026, 5, 2),
            createdAt: DateTime(2026, 5, 2),
          ),
        );
    final row = await (db.select(db.driveUploadJobs)
          ..where((t) => t.id.equals('j2')))
        .getSingle();
    expect(row.resumableUri, isNull);
    expect(row.driveFileId, isNull);
    expect(row.failureReason, isNull);
    expect(row.nextRetryAt, isNull);
  });

  test('nullable columns can be set to non-null values', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime(2026, 5, 2, 10, 0);
    await db.into(db.driveUploadJobs).insert(
          DriveUploadJobsCompanion.insert(
            id: 'j3',
            assignmentId: 'a-002',
            filePath: '/photos/p3.jpg',
            fileType: 'photo',
            fileName: 'p3.jpg',
            fileSizeBytes: 4096,
            capturedAt: now,
            createdAt: now,
            status: const Value('uploading'),
            resumableUri: const Value('https://upload.example.com/abc123'),
            driveFileId: const Value('1BxFgHkLmN'),
            retryCount: const Value(2),
            failureReason: const Value('network timeout'),
            nextRetryAt: Value(now.add(const Duration(minutes: 5))),
          ),
        );
    final row = await (db.select(db.driveUploadJobs)
          ..where((t) => t.id.equals('j3')))
        .getSingle();
    expect(row.status, 'uploading');
    expect(row.resumableUri, 'https://upload.example.com/abc123');
    expect(row.driveFileId, '1BxFgHkLmN');
    expect(row.retryCount, 2);
    expect(row.failureReason, 'network timeout');
    expect(row.nextRetryAt, isNotNull);
  });
}
