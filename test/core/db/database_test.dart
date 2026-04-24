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

    test('schema v1 materializes every table against SQLite', () async {
      // Force SQLite to execute CREATE TABLE for each registered table by
      // issuing a trivial SELECT. If any table's DDL is malformed (bad FK,
      // invalid default, typo'd column, etc.), Drift's lazy table creation
      // will throw here and the test fails with a helpful SQL error.
      for (final table in db.allTables) {
        await db
            .customSelect('SELECT 1 FROM ${table.actualTableName} LIMIT 1')
            .get();
      }

      // Round-trip one row to catch companion/serialization regressions on a
      // representative table.
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

    test('schemaVersion is 3', () {
      expect(db.schemaVersion, 3);
    });

    test('the DB registers exactly the 11 expected tables', () {
      final names = db.allTables.map((t) => t.actualTableName).toSet();
      expect(names, hasLength(11));
      expect(
        names,
        equals({
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
        }),
      );
    });
  });
}
