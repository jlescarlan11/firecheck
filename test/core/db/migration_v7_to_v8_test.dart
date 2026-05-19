// test/core/db/migration_v7_to_v8_test.dart
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

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

  // ── Real v7 → v8 migration test ────────────────────────────────────────────
  //
  // Opens an in-memory database pre-seeded with the v7 schema (no
  // drive_upload_jobs table), then lets AppDatabase run its onUpgrade
  // migration. Verifies that the table and its indexes are created correctly.
  test('migrates from v7 to v8: creates drive_upload_jobs table and indexes',
      () async {
    // Build a v7 schema in raw SQLite before Drift touches the database.
    // NativeDatabase.memory(setup:) fires on the raw sqlite3.Database before
    // any Drift migration runs, so we can set user_version = 7 and create the
    // v7 tables here.
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (rawDb) {
          // Mark this as a v7 database so Drift's onUpgrade fires with from=7.
          rawDb.execute('PRAGMA user_version = 7');

          // Create a representative subset of v7 tables. We only need enough
          // so that the migration's CREATE TABLE for drive_upload_jobs
          // succeeds; we don't need every column of every table.
          rawDb.execute('''
            CREATE TABLE IF NOT EXISTS enumerators (
              id TEXT NOT NULL PRIMARY KEY,
              name TEXT NOT NULL
            )
          ''');
          rawDb.execute('''
            CREATE TABLE IF NOT EXISTS assignments (
              id TEXT NOT NULL PRIMARY KEY,
              enumerator_id TEXT NOT NULL,
              campaign_id TEXT NOT NULL,
              boundary_polygon_geojson TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              submitted_at INTEGER,
              closed_remotely INTEGER NOT NULL DEFAULT 0,
              drive_modified_time TEXT,
              drive_folder_id TEXT
            )
          ''');
          // submissions / features: later migrations (v10→v11, v11→v12)
          // `addColumn` to these tables, so they must exist in the
          // seeded v7 schema even though this test is scoped to v7→v8.
          rawDb.execute('''
            CREATE TABLE IF NOT EXISTS submissions (
              id TEXT NOT NULL PRIMARY KEY,
              feature_id TEXT NOT NULL,
              submitted_by TEXT,
              does_not_exist INTEGER NOT NULL DEFAULT 0,
              remarks TEXT,
              sync_status TEXT NOT NULL DEFAULT 'draft',
              override_reason TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          rawDb.execute('''
            CREATE TABLE IF NOT EXISTS features (
              id TEXT NOT NULL PRIMARY KEY,
              assignment_id TEXT NOT NULL,
              feature_type TEXT NOT NULL,
              geometry_geojson TEXT NOT NULL,
              is_new INTEGER NOT NULL DEFAULT 0,
              status TEXT NOT NULL DEFAULT 'unfilled',
              created_at INTEGER NOT NULL
            )
          ''');
        },
      ),
    );
    addTearDown(db.close);

    // Touch the DB to trigger Drift's migration.
    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='drive_upload_jobs'",
        )
        .get();
    expect(tables, hasLength(1),
        reason: 'drive_upload_jobs table must exist after v7→v8 migration');

    final indexes = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='index' "
          "AND (name='drive_upload_jobs_status_idx' "
          "OR name='drive_upload_jobs_assignment_idx')",
        )
        .get();
    final indexNames =
        indexes.map((r) => r.data['name'] as String).toSet();
    expect(indexNames, contains('drive_upload_jobs_status_idx'));
    expect(indexNames, contains('drive_upload_jobs_assignment_idx'));

    // Verify the migrated table accepts a row insertion (smoke test).
    await db.customStatement('''
      INSERT INTO drive_upload_jobs
        (id, assignment_id, file_path, file_type, file_name,
         file_size_bytes, captured_at, created_at)
      VALUES
        ('test-id', 'a-001', '/photos/test.jpg', 'photo', 'test.jpg',
         1024, 0, 0)
    ''');
    final row = await db
        .customSelect(
          "SELECT id FROM drive_upload_jobs WHERE id='test-id'",
        )
        .getSingle();
    expect(row.data['id'], 'test-id');
  });
}
