import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/shapefile/export/export_validation_result.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_export_validator.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _seedBuilding(
  AppDatabase db, {
  required String assignmentId,
  required String featureId,
  required String submissionId,
}) async {
  final geoJson = jsonEncode({
    'type': 'Polygon',
    'coordinates': [
      [
        [120.0, 14.0], [121.0, 14.0], [121.0, 15.0],
        [120.0, 15.0], [120.0, 14.0],
      ],
    ],
  });
  await db.into(db.features).insert(FeaturesCompanion.insert(
    id: featureId,
    assignmentId: assignmentId,
    featureType: 'building',
    geometryGeojson: geoJson,
    status: const Value('complete'),
    createdAt: DateTime.now(),
  ));
  await db.into(db.submissions).insert(SubmissionsCompanion.insert(
    id: submissionId,
    featureId: featureId,
    syncStatus: const Value('ready_to_upload'),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ));
  await db.into(db.buildingAttributes).insert(
    BuildingAttributesCompanion.insert(
      submissionId: submissionId,
      fireFightingFacilitiesJson: const Value('[]'),
      fireLoadJson: const Value('[]'),
    ),
  );
}

// Complete building feature WITHOUT a buildingAttributes row.
// Simulates a feature that would be silently excluded by the exporter's inner join.
Future<void> _seedOrphanBuilding(
  AppDatabase db, {
  required String assignmentId,
  required String featureId,
  required String submissionId,
}) async {
  final geoJson = jsonEncode({
    'type': 'Polygon',
    'coordinates': [
      [
        [120.0, 14.0], [121.0, 14.0], [121.0, 15.0],
        [120.0, 15.0], [120.0, 14.0],
      ],
    ],
  });
  await db.into(db.features).insert(FeaturesCompanion.insert(
    id: featureId,
    assignmentId: assignmentId,
    featureType: 'building',
    geometryGeojson: geoJson,
    status: const Value('complete'),
    createdAt: DateTime.now(),
  ));
  await db.into(db.submissions).insert(SubmissionsCompanion.insert(
    id: submissionId,
    featureId: featureId,
    syncStatus: const Value('ready_to_upload'),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ));
  // Intentionally no buildingAttributes row
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
    status: const Value('complete'),
    createdAt: DateTime.now(),
  ));
  await db.into(db.submissions).insert(SubmissionsCompanion.insert(
    id: submissionId,
    featureId: featureId,
    syncStatus: const Value('ready_to_upload'),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ));
  await db.into(db.roadAttributes).insert(
    RoadAttributesCompanion.insert(
      submissionId: submissionId,
      roadFeaturesJson: const Value('[]'),
    ),
  );
}

// Complete road feature WITHOUT a roadAttributes row.
Future<void> _seedOrphanRoad(
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
    status: const Value('complete'),
    createdAt: DateTime.now(),
  ));
  await db.into(db.submissions).insert(SubmissionsCompanion.insert(
    id: submissionId,
    featureId: featureId,
    syncStatus: const Value('ready_to_upload'),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ));
  // Intentionally no roadAttributes row
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  ShapefileExportValidator makeValidator() =>
      ShapefileExportValidator(db: db);

  test('buildings layer empty → isValid false, buildings/emptyLayer error',
      () async {
    await _seedRoad(
        db, assignmentId: 'a1', featureId: 'r1', submissionId: 'sr1');
    final result = await makeValidator().validate('a1');
    expect(result.isValid, isFalse);
    expect(result.errors, hasLength(1));
    expect(result.errors.first.layer, ExportLayer.buildings);
    expect(result.errors.first.issue, ExportLayerIssue.emptyLayer);
  });

  test('roads layer empty → isValid false, roads/emptyLayer error', () async {
    await _seedBuilding(
        db, assignmentId: 'a1', featureId: 'b1', submissionId: 'sb1');
    final result = await makeValidator().validate('a1');
    expect(result.isValid, isFalse);
    expect(result.errors, hasLength(1));
    expect(result.errors.first.layer, ExportLayer.roads);
    expect(result.errors.first.issue, ExportLayerIssue.emptyLayer);
  });

  test('both layers empty → isValid false, two emptyLayer errors', () async {
    final result = await makeValidator().validate('a1');
    expect(result.isValid, isFalse);
    expect(result.errors, hasLength(2));
    expect(
      result.errors.map((e) => e.issue),
      everyElement(ExportLayerIssue.emptyLayer),
    );
  });

  test('building orphan → isValid false, buildings/missingRequiredFields',
      () async {
    await _seedOrphanBuilding(
        db, assignmentId: 'a1', featureId: 'b1', submissionId: 'sb1');
    await _seedRoad(
        db, assignmentId: 'a1', featureId: 'r1', submissionId: 'sr1');
    final result = await makeValidator().validate('a1');
    expect(result.isValid, isFalse);
    expect(result.errors, hasLength(1));
    expect(result.errors.first.layer, ExportLayer.buildings);
    expect(result.errors.first.issue, ExportLayerIssue.missingRequiredFields);
  });

  test('road orphan → isValid false, roads/missingRequiredFields', () async {
    await _seedBuilding(
        db, assignmentId: 'a1', featureId: 'b1', submissionId: 'sb1');
    await _seedOrphanRoad(
        db, assignmentId: 'a1', featureId: 'r1', submissionId: 'sr1');
    final result = await makeValidator().validate('a1');
    expect(result.isValid, isFalse);
    expect(result.errors, hasLength(1));
    expect(result.errors.first.layer, ExportLayer.roads);
    expect(result.errors.first.issue, ExportLayerIssue.missingRequiredFields);
  });

  test('all layers complete and valid → isValid true, no errors', () async {
    await _seedBuilding(
        db, assignmentId: 'a1', featureId: 'b1', submissionId: 'sb1');
    await _seedRoad(
        db, assignmentId: 'a1', featureId: 'r1', submissionId: 'sr1');
    final result = await makeValidator().validate('a1');
    expect(result.isValid, isTrue);
    expect(result.errors, isEmpty);
  });
}
