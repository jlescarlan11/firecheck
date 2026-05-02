// test/features/home/shapefile_export_notifier_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/shapefile/export/export_failure.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_exporter.dart';
import 'package:firecheck/features/home/data/shapefile_export_notifier.dart';
import 'package:firecheck/features/home/domain/export_state.dart';
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

ShapefileExportNotifier makeNotifier({
  required String assignmentId,
  required AppDatabase db,
  List<String>? capturedPaths,
}) {
  final exporter = ShapefileExporter(
    db: db,
    shareFile: (path) async {
      capturedPaths?.add(path);
    },
    tempDirOverride: Directory.systemTemp.createTempSync('notifier_test_'),
  );
  return ShapefileExportNotifier(
    assignmentId: assignmentId,
    exporter: exporter,
  );
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('initial state is ExportIdle', () {
    final notifier = makeNotifier(assignmentId: 'a1', db: db);
    expect(notifier.state, isA<ExportIdle>());
  });

  test('export with no features transitions Exporting then Failed', () async {
    final notifier = makeNotifier(assignmentId: 'a1', db: db);
    final states = <ExportState>[];
    notifier.addListener(states.add, fireImmediately: false);

    await notifier.export();

    expect(states, [
      isA<ExportExporting>(),
      isA<ExportFailed>(),
      isA<ExportIdle>(),
    ]);
    expect((states[1] as ExportFailed).failure, isA<NoCompletedFeatures>());
  });

  test('tapping export while Exporting is a no-op', () async {
    final notifier = makeNotifier(assignmentId: 'a1', db: db);
    final states = <ExportState>[];
    notifier.addListener(states.add, fireImmediately: false);

    final first = notifier.export();
    final second = notifier.export();

    await Future.wait([first, second]);

    expect(states.whereType<ExportExporting>(), hasLength(1));
  });

  test('after Failed state, notifier resets to Idle', () async {
    final notifier = makeNotifier(assignmentId: 'a1', db: db);
    await notifier.export();
    expect(notifier.state, isA<ExportIdle>());
  });

  test('successful export → Exporting then Done then Idle', () async {
    const assignmentId = 'a-success';
    await _seedBuilding(db, assignmentId: assignmentId, featureId: 'f1', submissionId: 's1');

    final capturedPaths = <String>[];
    final notifier = makeNotifier(
      assignmentId: assignmentId,
      db: db,
      capturedPaths: capturedPaths,
    );
    final states = <ExportState>[];
    notifier.addListener(states.add, fireImmediately: false);

    await notifier.export();

    expect(states, [isA<ExportExporting>(), isA<ExportDone>(), isA<ExportIdle>()]);
  });

  test('after successful export, notifier resets to Idle', () async {
    const assignmentId = 'a-success-2';
    await _seedBuilding(db, assignmentId: assignmentId, featureId: 'f1', submissionId: 's1');

    final notifier = makeNotifier(assignmentId: assignmentId, db: db);
    await notifier.export();

    expect(notifier.state, isA<ExportIdle>());
  });
}
