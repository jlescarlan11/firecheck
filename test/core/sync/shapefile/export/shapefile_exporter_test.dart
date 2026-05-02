// test/core/sync/shapefile/export/shapefile_exporter_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/shapefile/export/export_failure.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _seedBuilding(
  AppDatabase db, {
  required String assignmentId,
  required String featureId,
  required String submissionId,
  bool doesNotExist = false,
}) async {
  final geoJson = jsonEncode({
    'type': 'Polygon',
    'coordinates': [
      [
        [120.0, 14.0], [121.0, 14.0], [121.0, 15.0], [120.0, 15.0], [120.0, 14.0],
      ]
    ],
  });

  await db.into(db.features).insert(FeaturesCompanion.insert(
    id: featureId,
    assignmentId: assignmentId,
    featureType: 'building',
    geometryGeojson: geoJson,
    isNew: const Value(false),
    status: const Value('complete'),
    createdAt: DateTime.now(),
  ),);

  await db.into(db.submissions).insert(SubmissionsCompanion.insert(
    id: submissionId,
    featureId: featureId,
    doesNotExist: Value(doesNotExist),
    syncStatus: const Value('ready_to_upload'),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ),);

  await db.into(db.buildingAttributes).insert(BuildingAttributesCompanion.insert(
    submissionId: submissionId,
    cbmsId: const Value('C001'),
    buildingName: const Value('Test Hall'),
    ra9514Type: const Value('Group E'),
    storeys: const Value(3),
    material: const Value('Concrete'),
    costAmount: const Value(500000),
    fireFightingFacilitiesJson: const Value('["sprinkler","extinguisher"]'),
    fireLoadJson: const Value('["paper","chemicals"]'),
  ),);
}

Future<void> _seedRoad(
  AppDatabase db, {
  required String assignmentId,
  required String featureId,
  required String submissionId,
}) async {
  final geoJson = jsonEncode({
    'type': 'LineString',
    'coordinates': [[120.0, 14.0], [121.0, 14.5]],
  });

  await db.into(db.features).insert(FeaturesCompanion.insert(
    id: featureId,
    assignmentId: assignmentId,
    featureType: 'road',
    geometryGeojson: geoJson,
    isNew: const Value(false),
    status: const Value('complete'),
    createdAt: DateTime.now(),
  ),);

  await db.into(db.submissions).insert(SubmissionsCompanion.insert(
    id: submissionId,
    featureId: featureId,
    syncStatus: const Value('ready_to_upload'),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ),);

  await db.into(db.roadAttributes).insert(RoadAttributesCompanion.insert(
    submissionId: submissionId,
    roadName: const Value('Main St'),
    widthMeters: const Value(8),
    roadFeaturesJson: const Value('["Pedestrian"]'),
  ),);
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  ShapefileExporter makeExporter({List<String>? capturedPaths}) {
    return ShapefileExporter(
      db: db,
      shareFile: (path) async {
        capturedPaths?.add(path);
      },
      tempDirOverride: Directory.systemTemp.createTempSync('shp_test_'),
    );
  }

  test('two buildings + one road → export returns null (success)', () async {
    const assignmentId = 'assignment-001';
    await _seedBuilding(db, assignmentId: assignmentId, featureId: 'f1', submissionId: 's1');
    await _seedBuilding(db, assignmentId: assignmentId, featureId: 'f2', submissionId: 's2');
    await _seedRoad(db, assignmentId: assignmentId, featureId: 'f3', submissionId: 's3');

    final result = await makeExporter().export(assignmentId: assignmentId);

    expect(result, isNull);
  });

  test('two buildings + one road → ZIP file has 10 entries', () async {
    const assignmentId = 'assignment-001';
    await _seedBuilding(db, assignmentId: assignmentId, featureId: 'f1', submissionId: 's1');
    await _seedBuilding(db, assignmentId: assignmentId, featureId: 'f2', submissionId: 's2');
    await _seedRoad(db, assignmentId: assignmentId, featureId: 'f3', submissionId: 's3');

    final capturedPaths = <String>[];
    await makeExporter(capturedPaths: capturedPaths).export(assignmentId: assignmentId);

    expect(capturedPaths, hasLength(1));
    final zipBytes = await File(capturedPaths.first).readAsBytes();
    final archive = ZipDecoder().decodeBytes(zipBytes);
    expect(archive.files, hasLength(10));
  });

  test('only buildings → ZIP contains 5 building files only', () async {
    const assignmentId = 'assignment-002';
    await _seedBuilding(db, assignmentId: assignmentId, featureId: 'f1', submissionId: 's1');

    final capturedPaths = <String>[];
    await makeExporter(capturedPaths: capturedPaths).export(assignmentId: assignmentId);

    final zipBytes = await File(capturedPaths.first).readAsBytes();
    final archive = ZipDecoder().decodeBytes(zipBytes);
    expect(archive.files, hasLength(5));
    expect(archive.files.map((f) => f.name), everyElement(startsWith('buildings')));
  });

  test('no completed features → returns NoCompletedFeatures', () async {
    const assignmentId = 'assignment-003';
    final failure = await makeExporter().export(assignmentId: assignmentId);
    expect(failure, isA<NoCompletedFeatures>());
  });

  test('exported archive entries are non-empty for all required layer files',
      () async {
    const assignmentId = 'sanity-check-001';
    await _seedBuilding(db,
        assignmentId: assignmentId, featureId: 'b1', submissionId: 'sb1');
    await _seedRoad(db,
        assignmentId: assignmentId, featureId: 'r1', submissionId: 'sr1');

    final capturedPaths = <String>[];
    await makeExporter(capturedPaths: capturedPaths)
        .export(assignmentId: assignmentId);

    final zipBytes = await File(capturedPaths.first).readAsBytes();
    final archive = ZipDecoder().decodeBytes(zipBytes);

    for (final ext in ['.shp', '.shx', '.dbf']) {
      expect(
        archive.files.firstWhere((f) => f.name == 'buildings$ext').size,
        greaterThan(0),
        reason: 'buildings$ext must not be empty',
      );
      expect(
        archive.files.firstWhere((f) => f.name == 'roads$ext').size,
        greaterThan(0),
        reason: 'roads$ext must not be empty',
      );
    }
  });

  test('doesNotExist building is included in ZIP output', () async {
    const assignmentId = 'assignment-004';
    await _seedBuilding(
      db,
      assignmentId: assignmentId,
      featureId: 'f1',
      submissionId: 's1',
      doesNotExist: true,
    );

    final capturedPaths = <String>[];
    await makeExporter(capturedPaths: capturedPaths).export(assignmentId: assignmentId);

    final zipBytes = await File(capturedPaths.first).readAsBytes();
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final dbfEntry = archive.files.firstWhere((f) => f.name == 'buildings.dbf');
    expect(dbfEntry.content, isNotEmpty);
  });
}
