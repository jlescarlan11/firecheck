// test/core/sync/shapefile/export/shapefile_exporter_export_to_file_test.dart
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/shapefile/export/export_failure.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('shapefile_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('exportToFile returns NoCompletedFeatures when assignment has no complete features', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // Insert assignment + feature without completion
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
      id: 'a1',
      enumeratorId: 'e1',
      campaignId: 'c1',
      boundaryPolygonGeojson: '{}',
      createdAt: DateTime(2026),
    ));

    final exporter = ShapefileExporter(db: db, tempDirOverride: tempDir);
    final (failure, components) = await exporter.exportToFile(assignmentId: 'a1');

    expect(failure, isA<NoCompletedFeatures>());
    expect(components, isNull);
  });

  test('exportToFile writes loose .shp/.shx/.dbf/.prj components to tempDirOverride', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // Seed a complete building feature
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
      id: 'a1', enumeratorId: 'e1', campaignId: 'c1',
      boundaryPolygonGeojson: '{}', createdAt: DateTime(2026),
    ));
    await db.into(db.features).insert(FeaturesCompanion.insert(
      id: 'f1', assignmentId: 'a1', featureType: 'building',
      geometryGeojson: '{"type":"Polygon","coordinates":[[[0,0],[1,0],[1,1],[0,1],[0,0]]]}',
      status: const Value('complete'),
      createdAt: DateTime(2026),
    ));
    await db.into(db.submissions).insert(SubmissionsCompanion.insert(
      id: 's1', featureId: 'f1', createdAt: DateTime(2026), updatedAt: DateTime(2026),
    ));
    await db.into(db.buildingAttributes).insert(BuildingAttributesCompanion.insert(
      submissionId: 's1',
      fireFightingFacilitiesJson: const Value('[]'),
      fireLoadJson: const Value('[]'),
      costIsExact: const Value(false),
    ));

    final exporter = ShapefileExporter(db: db, tempDirOverride: tempDir);
    final (failure, components) = await exporter.exportToFile(assignmentId: 'a1');

    expect(failure, isNull);
    expect(components, isNotNull);
    expect(
      components!.map((c) => c.filename).toSet(),
      equals({'buildings.shp', 'buildings.shx', 'buildings.dbf', 'buildings.prj'}),
    );
    for (final c in components) {
      expect(File(c.path).existsSync(), isTrue,
          reason: '${c.filename} should exist on disk');
    }
  });

  test('exportToFile never invokes shareFile even when one is provided', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
      id: 'a1', enumeratorId: 'e1', campaignId: 'c1',
      boundaryPolygonGeojson: '{}', createdAt: DateTime(2026),
    ));
    await db.into(db.features).insert(FeaturesCompanion.insert(
      id: 'f1', assignmentId: 'a1', featureType: 'building',
      geometryGeojson: '{"type":"Polygon","coordinates":[[[0,0],[1,0],[1,1],[0,1],[0,0]]]}',
      status: const Value('complete'),
      createdAt: DateTime(2026),
    ));
    await db.into(db.submissions).insert(SubmissionsCompanion.insert(
      id: 's1', featureId: 'f1', createdAt: DateTime(2026), updatedAt: DateTime(2026),
    ));
    await db.into(db.buildingAttributes).insert(BuildingAttributesCompanion.insert(
      submissionId: 's1',
      fireFightingFacilitiesJson: const Value('[]'),
      fireLoadJson: const Value('[]'),
      costIsExact: const Value(false),
    ));

    var shareCalled = false;
    final exporter = ShapefileExporter(
      db: db,
      shareFile: (_) async { shareCalled = true; },
      tempDirOverride: tempDir,
    );
    final (failure, _) = await exporter.exportToFile(assignmentId: 'a1');

    expect(failure, isNull);
    expect(shareCalled, isFalse);
  });
}
