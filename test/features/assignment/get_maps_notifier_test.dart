// test/features/assignment/get_maps_notifier_test.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/device/storage_checker.dart';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';
import 'package:firecheck/core/drive/fake_drive_api.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/mapbox/offline_pack_adapter.dart';
import 'package:firecheck/core/sync/shapefile/dbf_parser.dart';
import 'package:firecheck/core/sync/shapefile/reprojector.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_importer.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_validator.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:firecheck/features/assignment/data/offline_tile_pack_repository.dart';
import 'package:firecheck/features/assignment/domain/get_maps_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/auth/data/fake_google_auth_repository.dart';
import 'package:firecheck/features/map/data/feature_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopImporter extends ShapefileImporter {
  _NoopImporter(AppDatabase db)
      : super(
          db: db,
          validator: const ShapefileValidator(),
          dbfParser: const DbfParser(),
          reprojector: Reprojector(),
        );

  int callCount = 0;

  @override
  Future<ImportResult> importInputZip(
    Uint8List zipBytes,
    String assignmentId,
    String driveModifiedTime,
    String driveFolderId,
    String enumeratorId,
  ) async {
    callCount++;
    await db.into(db.assignments).insertOnConflictUpdate(
          AssignmentsCompanion(
            id: Value(assignmentId),
            enumeratorId: Value(enumeratorId),
            campaignId: Value(assignmentId),
            boundaryPolygonGeojson: Value('{"type":"Polygon","coordinates":[[[0,0],[0,1],[1,1],[1,0],[0,0]]]}'),
            downloadedAt: Value(DateTime.now()),
            driveModifiedTime: Value(driveModifiedTime),
            driveFolderId: Value(driveFolderId),
            createdAt: Value(DateTime.now()),
          ),
        );
    return ImportResult(buildingCount: 1, roadCount: 1, boundaryGeojson: '{}');
  }
}

const _brgy001 = DriveAssignment(
  assignmentId: 'brgy-001',
  inputZipFileId: 'f1',
  inputZipModifiedTime: '2026-04-28T10:00:00Z',
  driveFolderId: 'folder-1',
);

GetMapsNotifier _makeNotifier({
  List<DriveAssignment>? assignments,
  Exception? listError,
  Exception? downloadError,
  int availableBytes = 100 * 1024 * 1024,
  List<DriveDownloadEvent>? downloadEvents,
  AppDatabase? db,
  _NoopImporter? importer,
}) {
  final database = db ?? AppDatabase.forTesting(NativeDatabase.memory());
  return GetMapsNotifier(
    assignmentRepo: AssignmentRepository(db: database),
    packRepo: OfflineTilePackRepository(database),
    packAdapter: FakeOfflinePackAdapter(),
    featureRepo: FeatureRepository(database),
    driveApi: FakeDriveApi(
      assignments: assignments ?? [_brgy001],
      listError: listError,
      downloadEvents: downloadEvents,
      downloadError: downloadError,
    ),
    googleAuthRepo: FakeGoogleAuthRepository(),
    shapefileImporter: importer ?? _NoopImporter(database),
    storageChecker: FakeStorageChecker(availableBytes: availableBytes),
  );
}

void main() {
  test('empty assignment list → GetMapsError with NoAssignmentsFailure', () async {
    final n = _makeNotifier(assignments: []);
    await n.start();
    expect(n.state, isA<GetMapsError>());
    expect((n.state as GetMapsError).failure, isA<NoAssignmentsFailure>());
  });

  test('Drive list error → GetMapsError', () async {
    final n = _makeNotifier(listError: Exception('network'));
    await n.start();
    expect(n.state, isA<GetMapsError>());
  });

  test('start → PickingAssignment with one assignment', () async {
    final n = _makeNotifier();
    await n.start();
    expect(n.state, isA<PickingAssignment>());
    final s = n.state as PickingAssignment;
    expect(s.assignments, hasLength(1));
    expect(s.selectedId, 'brgy-001');
  });

  test('selectAssignment updates selectedId', () async {
    const a2 = DriveAssignment(
      assignmentId: 'brgy-002',
      inputZipFileId: 'f2',
      inputZipModifiedTime: '2026-04-28T11:00:00Z',
      driveFolderId: 'folder-2',
    );
    final n = _makeNotifier(assignments: [_brgy001, a2]);
    await n.start();
    n.selectAssignment('brgy-002');
    expect((n.state as PickingAssignment).selectedId, 'brgy-002');
  });

  test('insufficient storage → InsufficientStorage state', () async {
    final n = _makeNotifier(availableBytes: 0);
    await n.start();
    await n.confirmDownload();
    expect(n.state, isA<InsufficientStorage>());
  });

  test('confirmDownload happy path → transitions through import to DownloadingTiles', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final imp = _NoopImporter(db);
    final n = _makeNotifier(db: db, importer: imp);
    await n.start();
    await n.confirmDownload();
    expect(n.state, isA<DownloadingTiles>());
    expect(imp.callCount, 1);
  });

  test('delta skip: alreadyDownloaded=true skips importer call', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.assignments).insert(
          AssignmentsCompanion(
            id: const Value('brgy-001'),
            enumeratorId: const Value('e'),
            campaignId: const Value('brgy-001'),
            boundaryPolygonGeojson: const Value('{"type":"Polygon","coordinates":[[[0,0],[0,1],[1,1],[1,0],[0,0]]]}'),
            driveModifiedTime: const Value('2026-04-28T10:00:00Z'),
            createdAt: Value(DateTime.now()),
          ),
        );
    final imp = _NoopImporter(db);
    final n = _makeNotifier(db: db, importer: imp);
    await n.start();
    final s = n.state as PickingAssignment;
    expect(s.assignments.first.alreadyDownloaded, isTrue);
    await n.confirmDownload();
    expect(imp.callCount, 0);
    expect(n.state, isA<DownloadingTiles>());
  });

  test('download stream error → GetMapsError', () async {
    final n = _makeNotifier(downloadError: Exception('timeout'));
    await n.start();
    await n.confirmDownload();
    expect(n.state, isA<GetMapsError>());
  });

  test('cancel during download → Cancelled', () async {
    final n = _makeNotifier();
    await n.start();
    unawaited(n.confirmDownload());
    await n.cancel();
    expect(n.state, isA<Cancelled>());
  });

  test('reset after cancel → Idle', () async {
    final n = _makeNotifier();
    await n.start();
    await n.cancel();
    n.reset();
    expect(n.state, isA<Idle>());
  });
}
