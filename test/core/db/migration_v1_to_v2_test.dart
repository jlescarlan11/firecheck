import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppDatabase schema v2', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async => db.close());

    test('PRAGMA foreign_keys is ON after open', () async {
      final result = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(result.data['foreign_keys'], 1);
    });

    test('all 5 phase-1 indexes exist on disk', () async {
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

    test('schemaVersion is 2', () {
      expect(db.schemaVersion, 2);
    });

    test('offline_tile_packs has mapbox_pack_id column, not maplibre_pack_id',
        () async {
      final rows = await db
          .customSelect('PRAGMA table_info(offline_tile_packs)')
          .get();
      final cols = rows.map((r) => r.data['name'] as String).toSet();
      expect(cols, contains('mapbox_pack_id'));
      expect(cols, isNot(contains('maplibre_pack_id')));
    });
  });
}
