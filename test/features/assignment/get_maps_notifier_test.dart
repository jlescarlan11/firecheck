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
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:firecheck/features/assignment/data/offline_tile_pack_repository.dart';
import 'package:firecheck/features/assignment/domain/get_maps_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/auth/data/fake_google_auth_repository.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_validator.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/validation_report.dart';
import 'package:firecheck/core/validation/validation_failure_reporter.dart';
import 'package:firecheck/features/map/data/feature_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopImporter extends ShapefileImporter {
  _NoopImporter(AppDatabase db)
      : super(
          db: db,
          dbfParser: const DbfParser(),
          reprojector: Reprojector(),
        );

  int callCount = 0;

  @override
  Future<ImportResult> importShapefiles(
    Map<String, Uint8List> files,
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

class _SpyRule extends ShapefileValidationRule {
  const _SpyRule(this._outcome);
  final RuleOutcome _outcome;
  @override
  RuleOutcome check(Map<String, Uint8List> files, Map<String, String> expectedMd5s) =>
      _outcome;
}

const _brgy001 = DriveAssignment(
  assignmentId: 'brgy-001',
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
  ShapefileValidator? validator,
  ValidationFailureReporter? reporter,
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
    validator: validator ?? ShapefileValidator(rules: [const _SpyRule(RulePassed())]),
    reporter: reporter ?? FakeValidationFailureReporter(),
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
      inputZipModifiedTime: '2026-04-28T11:00:00Z',
      driveFolderId: 'folder-2',
    );
    final n = _makeNotifier(assignments: [_brgy001, a2]);
    await n.start();
    n.selectAssignment('brgy-002');
    expect((n.state as PickingAssignment).selectedId, 'brgy-002');
  });

  test('confirmDownload emits PreparingDownload immediately before any network call (US-20)', () async {
    final n = _makeNotifier();
    await n.start();
    expect(n.state, isA<PickingAssignment>());

    final states = <GetMapsState>[];
    n.addListener(states.add, fireImmediately: false);

    unawaited(n.confirmDownload());
    await Future.microtask(() {});

    expect(states.first, isA<PreparingDownload>());
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

  group('US-19 shapefile validation', () {
    test('state sequence includes ValidatingShapefiles then GetMapsError(isRetryable: false) on fatal validation', () async {
      final fakeReporter = FakeValidationFailureReporter();
      final fatalValidator = ShapefileValidator(
        rules: [_SpyRule(const RuleFatal(ruleName: 'checksum', userMessage: 'Damaged.'))],
      );
      final notifier = _makeNotifier(
        assignments: [_brgy001],
        validator: fatalValidator,
        reporter: fakeReporter,
      );
      final states = <GetMapsState>[];
      notifier.addListener(states.add);

      await notifier.start();
      await notifier.confirmDownload();

      expect(states.any((s) => s is ValidatingShapefiles), isTrue);
      final errorState = states.whereType<GetMapsError>().last;
      expect(errorState.isRetryable, isFalse);
      expect(errorState.failure, isA<ShapefileValidationFailure>());
      expect((errorState.failure as ShapefileValidationFailure).ruleName, 'checksum');
      expect(fakeReporter.calls, hasLength(1));
      expect(fakeReporter.calls.first['failedRule'], 'checksum');
    });

    test('state reaches ShapefileWarning when validation has warnings only', () async {
      final warningValidator = ShapefileValidator(
        rules: [_SpyRule(const RuleWarning(userMessage: 'Large file.'))],
      );
      final notifier = _makeNotifier(
        assignments: [_brgy001],
        validator: warningValidator,
      );
      final states = <GetMapsState>[];
      notifier.addListener(states.add);

      await notifier.start();
      await notifier.confirmDownload();

      expect(states.last, isA<ShapefileWarning>());
      expect((states.last as ShapefileWarning).warnings, hasLength(1));
    });

    test('acknowledgeWarning proceeds to ImportingShapefiles after ShapefileWarning', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final importer = _NoopImporter(db);
      final warningValidator = ShapefileValidator(
        rules: [_SpyRule(const RuleWarning(userMessage: 'w'))],
      );
      final notifier = _makeNotifier(
        assignments: [_brgy001],
        validator: warningValidator,
        db: db,
        importer: importer,
      );
      final states = <GetMapsState>[];
      notifier.addListener(states.add);

      await notifier.start();
      await notifier.confirmDownload();
      expect(states.last, isA<ShapefileWarning>());

      await notifier.acknowledgeWarning();
      expect(states.any((s) => s is ImportingShapefiles), isTrue);
    });

    test('network error during download is retryable', () async {
      final notifier = _makeNotifier(
        assignments: [_brgy001],
        downloadError: Exception('timeout'),
      );
      final states = <GetMapsState>[];
      notifier.addListener(states.add);

      await notifier.start();
      await notifier.confirmDownload();

      final errorState = states.whereType<GetMapsError>().last;
      expect(errorState.isRetryable, isTrue);
    });

    test('retryDownload re-attempts download after retryable error', () async {
      final notifier = _makeNotifier(
        assignments: [_brgy001],
        downloadError: Exception('timeout'),
      );
      final states = <GetMapsState>[];
      notifier.addListener(states.add);

      await notifier.start();
      await notifier.confirmDownload();
      expect(states.last, isA<GetMapsError>());
      expect((states.last as GetMapsError).isRetryable, isTrue);

      final statesBeforeRetry = states.length;
      await notifier.retryDownload();
      // retryDownload re-enters _downloadAndValidate → DownloadingShapefiles is emitted
      expect(
        states.skip(statesBeforeRetry).any((s) => s is DownloadingShapefiles),
        isTrue,
      );
    });
  });
}
