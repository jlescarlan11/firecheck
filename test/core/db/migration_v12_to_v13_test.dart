import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifies the v12 → v13 migration rewrites legacy sync_job entity_type
/// strings so an offline queue from a prior install doesn't dead-letter
/// after the legacy handlers are removed.
void main() {
  test(
    'legacy submission / new_feature sync_jobs are rewritten to the new types',
    () async {
      final db = AppDatabase.forTesting(
        NativeDatabase.memory(
          setup: (rawDb) {
            // Seed the DB at v12 so onUpgrade fires only the v12→v13
            // step. Below we materialise just the columns the rewrite
            // statements touch — the test doesn't need a fully
            // representative schema.
            rawDb.execute('PRAGMA user_version = 12');
            rawDb.execute('''
              CREATE TABLE IF NOT EXISTS sync_jobs (
                id TEXT NOT NULL PRIMARY KEY,
                entity_type TEXT NOT NULL,
                entity_id TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'pending',
                blocks_on_submission_id TEXT,
                attempts INTEGER NOT NULL DEFAULT 0,
                last_error TEXT,
                next_retry_at INTEGER,
                created_at INTEGER NOT NULL
              )
            ''');
            // Two legacy rows, one already-migrated row, one unrelated
            // type (photo). Only the first two should be rewritten.
            rawDb.execute(
              "INSERT INTO sync_jobs(id, entity_type, entity_id, created_at) "
              "VALUES ('j1', 'submission', 's1', 0), "
              "       ('j2', 'new_feature', 'f1', 0), "
              "       ('j3', 'attribution_upload', 's2', 0), "
              "       ('j4', 'photo', 'p1', 0)",
            );
          },
        ),
      );
      addTearDown(db.close);

      // Touch the DB so onUpgrade fires.
      final jobs = await (db.select(db.syncJobs)).get();
      expect(jobs, hasLength(4));

      Future<String> typeOf(String id) async {
        final j = await (db.select(db.syncJobs)
              ..where((t) => t.id.equals(id)))
            .getSingle();
        return j.entityType;
      }

      expect(await typeOf('j1'), 'attribution_upload',
          reason: 'legacy submission rewrites to attribution_upload');
      expect(await typeOf('j2'), 'new_feature_upload',
          reason: 'legacy new_feature rewrites to new_feature_upload');
      expect(await typeOf('j3'), 'attribution_upload',
          reason: 'already-new rows are left alone');
      expect(await typeOf('j4'), 'photo',
          reason: 'unrelated types are left alone');
    },
  );
}
