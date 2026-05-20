// test/core/db/migration_v13_to_v14_test.dart
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schemaVersion is at least 14', () {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(14));
  });

  test('assignments.name is nullable and defaults to null', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: '00000000-0000-0000-0000-000000000001',
            enumeratorId: 'e1',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: DateTime.now(),
          ),
        );
    final row = await (db.select(db.assignments)
          ..where((t) => t.id.equals('00000000-0000-0000-0000-000000000001')))
        .getSingle();
    expect(row.name, isNull);
  });

  test('assignments.name can store the Drive folder display name', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: '00000000-0000-0000-0000-000000000002',
            enumeratorId: 'e1',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            name: const Value('cebu'),
            createdAt: DateTime.now(),
          ),
        );
    final row = await (db.select(db.assignments)
          ..where((t) => t.id.equals('00000000-0000-0000-0000-000000000002')))
        .getSingle();
    expect(row.name, 'cebu');
  });

  test('features.externalCode is nullable and defaults to null', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: '00000000-0000-0000-0000-000000000003',
            enumeratorId: 'e1',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: DateTime.now(),
          ),
        );
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f1',
            assignmentId: '00000000-0000-0000-0000-000000000003',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: DateTime.now(),
          ),
        );
    final row = await (db.select(db.features)
          ..where((t) => t.id.equals('f1')))
        .getSingle();
    expect(row.externalCode, isNull);
  });

  test('features.externalCode stores original DBF feat_id', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: '00000000-0000-0000-0000-000000000004',
            enumeratorId: 'e1',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: DateTime.now(),
          ),
        );
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f2',
            assignmentId: '00000000-0000-0000-0000-000000000004',
            featureType: 'building',
            geometryGeojson: '{}',
            externalCode: const Value('BRG-001'),
            createdAt: DateTime.now(),
          ),
        );
    final row = await (db.select(db.features)
          ..where((t) => t.id.equals('f2')))
        .getSingle();
    expect(row.externalCode, 'BRG-001');
  });
}
