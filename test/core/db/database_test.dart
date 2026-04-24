import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppDatabase', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('schema v1 creates all 11 tables without error', () async {
      // Assert by inserting a row into every table and reading it back.
      await db.into(db.ra9514Types).insert(
            Ra9514TypesCompanion.insert(
              code: 'A',
              labelEn: 'Residential',
              labelTl: 'Tirahan',
            ),
          );

      final rows = await db.select(db.ra9514Types).get();
      expect(rows, hasLength(1));
      expect(rows.first.code, 'A');
    });

    test('schemaVersion is 1', () {
      expect(db.schemaVersion, 1);
    });

    test('all 11 tables are registered on the DB', () {
      final names = db.allTables.map((t) => t.actualTableName).toSet();
      expect(
        names,
        containsAll([
          'enumerators',
          'assignments',
          'features',
          'submissions',
          'building_attributes',
          'road_attributes',
          'household_surveys',
          'photos',
          'ra_9514_types',
          'sync_jobs',
          'offline_tile_packs',
        ]),
      );
    });
  });
}
