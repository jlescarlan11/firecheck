import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/app.dart';
import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/device/storage_checker.dart';
import 'package:firecheck/core/drive/drive_api.dart';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';
import 'package:firecheck/core/sync/data/fake_sync_api.dart';
import 'package:firecheck/core/sync/data/sync_api.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_importer.dart';
import 'package:firecheck/core/validation/validation_failure_reporter.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/map/presentation/map_providers.dart';
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Set up at least one complete feature (Building)', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final renderer = FakeMapRenderer();
    const boundary =
        '{"type":"Polygon","coordinates":[[[123.88200,10.31720],[123.88340,10.31720],[123.88340,10.31900],[123.88200,10.31900],[123.88200,10.31720]]]}';

    // Seed a demo assignment so we are not in a "clean state" that blocks adding.
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'admin',
            campaignId: 'c1',
            boundaryPolygonGeojson: boundary,
            createdAt: DateTime.now(),
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          mapRendererProvider.overrideWithValue(renderer),
          currentUserIdProvider.overrideWith((ref) => 'admin'),
          driveApiProvider.overrideWith((ref) => FakeDriveApi()),
          shapefileImporterProvider.overrideWith((ref) => FakeShapefileImporter(db: db)),
          storageCheckerProvider.overrideWithValue(const FakeStorageChecker()),
          validationFailureReporterProvider
              .overrideWithValue(FakeValidationFailureReporter()),
        ],
        child: const FireCheckApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Tap Gather Data
    await tester.tap(find.text('Gather Data'));
    await tester.pumpAndSettle();

    // 2. Enter Add Mode (+ pill)
    await tester.tap(find.byKey(const Key('map.add-feature-pill')));
    await tester.pumpAndSettle();

    // 3. Drop vertices (simulated as long-press for Point-based add)
    // simulateLongPress was removed in plan Task 8; this whole test is
    // skipped and will be rewritten in plan Task 12 for the sketch flow.
    await renderer.simulateMapTap(10.31810, 123.88270);
    await tester.pumpAndSettle();

    // 4. Choose Building
    await tester.tap(find.byKey(const Key('feature-type-picker.building')));
    await tester.pumpAndSettle();

    // 5. Fill required fields in detail screen
    await tester.enterText(find.byKey(const Key('field.building_name')), 'Test Building');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('field.ra_9514_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Group A').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('field.storeys')), '2');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('field.material')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Concrete').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('field.cost_exact')), '1000000');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Wood furniture'));
    await tester.pumpAndSettle();

    final features = await db.select(db.features).get();
    final featureId = features.first.id;
    final submissions = await (db.select(db.submissions)..where((t) => t.featureId.equals(featureId))).get();
    final submissionId = submissions.first.id;
    
    await db.into(db.photos).insert(PhotosCompanion.insert(
      id: 'p1',
      submissionId: submissionId,
      localPath: '/tmp/test.jpg',
      capturedAt: DateTime.now(),
      createdAt: DateTime.now(),
    ));
    await tester.pumpAndSettle();

    // 6. Tap Done
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // 7. Back on map, verify feature status is complete (green)
    final updatedFeature = await (db.select(db.features)..where((t) => t.id.equals(featureId))).getSingle();
    expect(updatedFeature.status, 'complete');
    // skip reason: rewritten in plan Task 12 for sketch flow
  }, skip: true);
}

class FakeDriveApi implements DriveApi {
  @override
  Future<int> getTotalSize(String assignmentId) async => 0;
  @override
  Future<List<DriveAssignment>> listAssignments() async => [];
  @override
  Stream<DriveDownloadEvent> downloadShapefiles(String assignmentId) async* {}
  @override
  Future<({String folderPath, String folderUrl})> uploadAssignmentFiles({
    required String enumeratorId,
    required String assignmentId,
    required List<({String filename, Uint8List bytes})> files,
  }) async => (folderPath: 'FieldData/admin/2026-05-15/', folderUrl: 'https://drive.google.com/...');
}

class FakeShapefileImporter implements ShapefileImporter {
  FakeShapefileImporter({required this.db});
  @override
  final AppDatabase db;
  @override
  get dbfParser => throw UnimplementedError();
  @override
  get reprojector => throw UnimplementedError();
  @override
  Future<ImportResult> importShapefiles(Map<String, Uint8List> files, String assignmentId, String driveModifiedTime, String driveFolderId, String enumeratorId) async {
    return const ImportResult(buildingCount: 0, roadCount: 0, boundaryGeojson: '{}');
  }
}

class FakeStorageChecker implements StorageChecker {
  const FakeStorageChecker();
  @override
  Future<int> getAvailableBytes() async => 1024 * 1024 * 1024;
}

class FakeValidationFailureReporter implements ValidationFailureReporter {
  @override
  Future<void> report({
    required String assignmentId,
    required String enumeratorId,
    required String failedRule,
    required String message,
    String? fileChecksum,
  }) async {}
}

