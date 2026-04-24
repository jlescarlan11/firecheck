import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppDatabase schema v3', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async => db.close());

    test('schemaVersion is 3', () {
      expect(db.schemaVersion, 3);
    });

    test('PRAGMA foreign_keys remains ON', () async {
      final result = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(result.data['foreign_keys'], 1);
    });

    test('submissions has override_reason column', () async {
      final rows =
          await db.customSelect('PRAGMA table_info(submissions)').get();
      final cols = rows.map((r) => r.data['name'] as String).toSet();
      expect(cols, contains('override_reason'));
    });

    test('phase-1 indexes still present', () async {
      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final names = rows.map((r) => r.data['name'] as String).toSet();
      expect(
        names,
        containsAll([
          'features_assignment_id_idx',
          'submissions_feature_id_idx',
          'photos_submission_id_idx',
          'sync_jobs_status_retry_idx',
          'building_attrs_ra9514_type_idx',
        ]),
      );
    });
  });
}
