// lib/features/assignment/presentation/assignment_providers.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/device/storage_checker.dart';
import 'package:firecheck/core/drive/drive_api.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/mapbox/offline_pack_adapter.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_importer.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_validator.dart';
import 'package:firecheck/core/validation/validation_failure_reporter.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:firecheck/features/assignment/data/offline_tile_pack_repository.dart';
import 'package:firecheck/features/assignment/domain/get_maps_state.dart';
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/map/data/feature_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

// ── base providers ──────────────────────────────────────────────────────────

final assignmentRepositoryProvider = Provider<AssignmentRepository>((ref) {
  return AssignmentRepository(db: ref.watch(appDatabaseProvider));
});

final offlineTilePackRepositoryProvider =
    Provider<OfflineTilePackRepository>((ref) {
  return OfflineTilePackRepository(ref.watch(appDatabaseProvider));
});

final offlinePackAdapterProvider = Provider<OfflinePackAdapter>((ref) {
  return FakeOfflinePackAdapter();
});

final featureRepositoryProvider = Provider<FeatureRepository>((ref) {
  return FeatureRepository(ref.watch(appDatabaseProvider));
});

/// Overridden in main.dart with GoogleDriveApi.
final driveApiProvider = Provider<DriveApi>((ref) {
  throw UnimplementedError('Override driveApiProvider in main.dart');
});

/// Overridden in main.dart with ShapefileImporter backed by real DB.
final shapefileImporterProvider = Provider<ShapefileImporter>((ref) {
  throw UnimplementedError('Override shapefileImporterProvider in main.dart');
});

/// Overridden in main.dart with DeviceStorageChecker.
final storageCheckerProvider = Provider<StorageChecker>((ref) {
  throw UnimplementedError('Override storageCheckerProvider in main.dart');
});

// ── notifier ────────────────────────────────────────────────────────────────

class GetMapsNotifier extends StateNotifier<GetMapsState> {
  GetMapsNotifier({
    required this.assignmentRepo,
    required this.packRepo,
    required this.packAdapter,
    required this.featureRepo,
    required this.driveApi,
    required this.googleAuthRepo,
    required this.shapefileImporter,
    required this.storageChecker,
    required this.validator,
    required this.reporter,
  }) : super(const Idle());

  final AssignmentRepository assignmentRepo;
  final OfflineTilePackRepository packRepo;
  final OfflinePackAdapter packAdapter;
  final FeatureRepository featureRepo;
  final DriveApi driveApi;
  final GoogleAuthRepository googleAuthRepo;
  final ShapefileImporter shapefileImporter;
  final StorageChecker storageChecker;
  final ShapefileValidator validator;
  final ValidationFailureReporter reporter;

  static const _styleUri = 'mapbox://styles/mapbox/streets-v12';
  static const _minZoom = 12;
  static const _maxZoom = 17;

  bool _cancelled = false;
  DriveAssignment? _selectedAssignment;
  String? _enumeratorId;

  Future<void> start() async {
    _cancelled = false;
    state = const DiscoveringAssignments();

    List<DriveAssignment> rawAssignments;
    try {
      rawAssignments = await driveApi.listAssignments();
    } catch (e) {
      if (!mounted) return;
      state = GetMapsError(NetworkFailure(e.toString()), isRetryable: true);
      return;
    }

    if (!mounted) return;
    if (rawAssignments.isEmpty) {
      state = const GetMapsError(NoAssignmentsFailure());
      return;
    }

    // Delta check: mark assignments whose modifiedTime matches stored value.
    final assignments = await Future.wait(
      rawAssignments.map((a) async {
        final stored = await assignmentRepo.getDriveModifiedTime(a.assignmentId);
        return stored == a.inputZipModifiedTime
            ? a.copyWith(alreadyDownloaded: true)
            : a;
      }),
    );

    if (!mounted) return;
    state = PickingAssignment(
      assignments: assignments,
      selectedId: assignments.first.assignmentId,
    );
  }

  void selectAssignment(String id) {
    final s = state;
    if (s is! PickingAssignment) return;
    state = PickingAssignment(assignments: s.assignments, selectedId: id);
  }

  Future<void> confirmDownload() async {
    final s = state;
    if (s is! PickingAssignment) return;

    // Show spinner immediately so the user sees feedback within one frame (US-20).
    state = const PreparingDownload();

    final selected =
        s.assignments.firstWhere((a) => a.assignmentId == s.selectedId);
    _selectedAssignment = selected;

    // Delta skip — already imported, go straight to tile download
    if (selected.alreadyDownloaded) {
      _enumeratorId = await googleAuthRepo.getEnumeratorId();
      if (!mounted) return;
      await _startTileDownload();
      return;
    }

    // Storage pre-check
    final needed = await driveApi.getTotalSize(selected.assignmentId);
    final available = await storageChecker.getAvailableBytes();
    if (!mounted) return;
    if (available < needed) {
      state = InsufficientStorage(requiredBytes: needed, availableBytes: available);
      return;
    }

    _enumeratorId = await googleAuthRepo.getEnumeratorId();
    await _downloadAndValidate(selected, needed);
  }

  Future<void> acknowledgeWarning() async {
    final s = state;
    if (s is! ShapefileWarning) return;
    final selected = _selectedAssignment;
    if (selected == null) return;
    await _doImport(selected, s.pendingFiles);
  }

  Future<void> retryDownload() async {
    final s = state;
    if (s is! GetMapsError || !s.isRetryable) return;
    final selected = _selectedAssignment;
    if (selected == null) return;
    final needed = await driveApi.getTotalSize(selected.assignmentId);
    await _downloadAndValidate(selected, needed);
  }

  Future<void> _downloadAndValidate(
    DriveAssignment selected,
    int totalBytes,
  ) async {
    state = DownloadingShapefiles(downloaded: 0, total: totalBytes);
    Map<String, Uint8List>? shapefiles;
    Map<String, String> shapeMd5s = {};

    try {
      await for (final event
          in driveApi.downloadShapefiles(selected.assignmentId)) {
        if (_cancelled || !mounted) return;
        switch (event) {
          case DriveDownloadProgress(:final downloaded, :final total):
            state = DownloadingShapefiles(downloaded: downloaded, total: total);
          case DriveDownloadComplete(:final files, :final expectedMd5s):
            shapefiles = files;
            shapeMd5s = expectedMd5s;
        }
      }
    } catch (e) {
      if (!mounted) return;
      state = GetMapsError(NetworkFailure(e.toString()), isRetryable: true);
      return;
    }

    if (_cancelled || !mounted) return;
    if (shapefiles == null) {
      state = GetMapsError(
        const NetworkFailure('Download completed with no data'),
        isRetryable: true,
      );
      return;
    }

    state = const ValidatingShapefiles();
    final report = validator.validate(shapefiles, shapeMd5s);

    if (report.hasFatals) {
      final fatal = report.fatal!;
      unawaited(reporter.report(
        assignmentId: selected.assignmentId,
        enumeratorId: _enumeratorId ?? '',
        failedRule: fatal.ruleName,
        message: fatal.userMessage,
        fileChecksum: fatal.computedChecksum,
      ));
      // Log only — attempt import anyway with whatever files are available.
    }

    if (!report.hasFatals && report.hasWarnings) {
      if (!mounted) return;
      state = ShapefileWarning(
        warnings: report.warnings.map((w) => w.userMessage).toList(),
        pendingFiles: shapefiles,
        expectedMd5s: shapeMd5s,
      );
      return;
    }

    await _doImport(selected, shapefiles);
  }

  Future<void> _doImport(
    DriveAssignment selected,
    Map<String, Uint8List> files,
  ) async {
    if (!mounted) return;
    state = const ImportingShapefiles();
    try {
      await shapefileImporter.importShapefiles(
        files,
        selected.assignmentId,
        selected.inputZipModifiedTime,
        selected.driveFolderId,
        _enumeratorId ?? '',
      );
    } catch (e) {
      if (!mounted) return;
      // Non-fatal — let the user open the map even if import failed.
      state = const Ready(featureCount: 0, totalBytes: 0);
      return;
    }
    if (!mounted) return;
    await _startTileDownload();
  }

  Future<void> _startTileDownload() async {
    if (!mounted) return;
    final assignment = await assignmentRepo.getCurrentAssignment();
    if (!mounted) return;
    if (assignment == null) {
      // Import didn't create an assignment — let user open the map anyway.
      state = const Ready(featureCount: 0, totalBytes: 0);
      return;
    }

    final packId = const Uuid().v4();
    await packRepo.upsert(
      id: packId,
      assignmentId: assignment.id,
      regionBoundsGeojson: assignment.boundaryPolygonGeojson,
    );

    if (!mounted) return;
    state = const DownloadingTiles(downloadedBytes: 0, totalBytes: 0);

    final stream = packAdapter.createPack(
      regionGeojson: assignment.boundaryPolygonGeojson,
      styleUri: _styleUri,
      minZoom: _minZoom,
      maxZoom: _maxZoom,
    );

    try {
      await for (final event in stream) {
        if (!mounted) return;
        switch (event) {
          case OfflinePackProgress(:final downloaded, :final total):
            state =
                DownloadingTiles(downloadedBytes: downloaded, totalBytes: total);
            await packRepo.updateProgress(packId, downloaded, total);
          case OfflinePackComplete():
            await packRepo.markReady(packId);
            final features = await featureRepo
                .watchFeaturesForAssignment(assignment.id)
                .first;
            final currentTotal = state is DownloadingTiles
                ? (state as DownloadingTiles).totalBytes
                : 0;
            state = Ready(
                featureCount: features.length, totalBytes: currentTotal);
            return;
          case OfflinePackError(:final message):
            await packRepo.markError(packId, message);
            // Non-fatal — open the map without offline tiles.
            final features = await featureRepo
                .watchFeaturesForAssignment(assignment.id)
                .first;
            state = Ready(featureCount: features.length, totalBytes: 0);
            return;
        }
      }
    } on Object catch (_) {
      if (!mounted) return;
      final features = await featureRepo
          .watchFeaturesForAssignment(assignment.id)
          .first;
      state = Ready(featureCount: features.length, totalBytes: 0);
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    await packAdapter.cancelAllPacks();
    if (!mounted) return;
    state = const Cancelled();
  }

  void reset() {
    _cancelled = false;
    _selectedAssignment = null;
    _enumeratorId = null;
    state = const Idle();
  }
}

// ── providers ────────────────────────────────────────────────────────────────

final shapefileValidatorProvider = Provider<ShapefileValidator>((ref) {
  return ShapefileValidator();
});

/// Overridden in main.dart with SupabaseValidationFailureReporter.
final validationFailureReporterProvider =
    Provider<ValidationFailureReporter>((ref) {
  throw UnimplementedError(
      'Override validationFailureReporterProvider in main.dart');
});

final getMapsNotifierProvider =
    StateNotifierProvider<GetMapsNotifier, GetMapsState>((ref) {
  return GetMapsNotifier(
    assignmentRepo: ref.watch(assignmentRepositoryProvider),
    packRepo: ref.watch(offlineTilePackRepositoryProvider),
    packAdapter: ref.watch(offlinePackAdapterProvider),
    featureRepo: ref.watch(featureRepositoryProvider),
    driveApi: ref.watch(driveApiProvider),
    googleAuthRepo: ref.watch(googleAuthRepositoryProvider),
    shapefileImporter: ref.watch(shapefileImporterProvider),
    storageChecker: ref.watch(storageCheckerProvider),
    validator: ref.watch(shapefileValidatorProvider),
    reporter: ref.watch(validationFailureReporterProvider),
  );
});

final currentAssignmentProvider = StreamProvider<Assignment?>((ref) {
  return ref.watch(assignmentRepositoryProvider).watchCurrentAssignment();
});
