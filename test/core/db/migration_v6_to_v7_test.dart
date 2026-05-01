// test/core/db/migration_v6_to_v7_test.dart
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schemaVersion is at least 7', () {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(7));
  });

  test('assignments.driveModifiedTime is nullable and defaults to null', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'e1',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: DateTime.now(),
          ),
        );
    final row = await (db.select(db.assignments)
          ..where((t) => t.id.equals('a1')))
        .getSingle();
    expect(row.driveModifiedTime, isNull);
    expect(row.driveFolderId, isNull);
  });

  test('assignments.driveModifiedTime and driveFolderId can be set', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a2',
            enumeratorId: 'e1',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            driveModifiedTime: const Value('2026-04-28T10:00:00Z'),
            driveFolderId: const Value('folder-abc'),
            createdAt: DateTime.now(),
          ),
        );
    final row = await (db.select(db.assignments)
          ..where((t) => t.id.equals('a2')))
        .getSingle();
    expect(row.driveModifiedTime, '2026-04-28T10:00:00Z');
    expect(row.driveFolderId, 'folder-abc');
  });
}
