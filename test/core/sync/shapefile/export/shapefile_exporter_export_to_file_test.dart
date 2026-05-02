// test/core/sync/shapefile/export/shapefile_exporter_export_to_file_test.dart
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/shapefile/export/export_failure.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_exporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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
    final (failure, path) = await exporter.exportToFile(assignmentId: 'a1');

    expect(failure, isA<NoCompletedFeatures>());
    expect(path, isNull);
  });

  test('exportToFile writes ZIP to tempDirOverride and returns path', () async {
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
    final (failure, path) = await exporter.exportToFile(assignmentId: 'a1');

    expect(failure, isNull);
    expect(path, isNotNull);
    expect(p.extension(path!), '.zip');
    expect(File(path).existsSync(), isTrue);
  });
}
