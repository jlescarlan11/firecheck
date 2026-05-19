// lib/features/assignment/presentation/assignment_providers.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/device/storage_checker.dart';
import 'package:firecheck/core/drive/drive_api.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';
import 'package:firecheck/core/drive/ftp_credentials.dart';
import 'package:firecheck/core/drive/ftp_map_source_api.dart';
import 'package:firecheck/core/drive/transport_source.dart';
import 'package:firecheck/core/forms/field_requirements_providers.dart';
import 'package:firecheck/core/forms/field_requirements_store.dart';
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
    this.onRequirementsUpdated,
  }) : super(const Idle());

  /// Invoked after a freshly downloaded `field_requirements.txt` is
  /// written to local storage so the form layer re-reads it. Optional so
  /// tests can construct the notifier without a Riverpod ref.
  final void Function()? onRequirementsUpdated;

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

  /// Active map-source transport (Issue #45). Defaults to Google Drive
  /// (which uses the injected [driveApi]). When set to FTP the notifier
  /// builds an [FtpMapSourceApi] on the fly from the supplied credentials.
  TransportSource _transport = TransportSource.googleDrive;
  FtpCredentials? _ftpCredentials;

  void setTransport(TransportSource transport, {FtpCredentials? ftp}) {
    _transport = transport;
    _ftpCredentials = ftp;
  }

  /// Resolves the [DriveApi] for the currently selected transport.
  DriveApi get _activeSource {
    switch (_transport) {
      case TransportSource.googleDrive:
        return driveApi;
      case TransportSource.ftp:
        final c = _ftpCredentials;
        if (c == null || !c.isComplete) {
          throw StateError(
            'FTP transport selected but credentials are missing — fill in '
            'the host/user/password fields before starting.',
          );
        }
        return FtpMapSourceApi(c);
    }
  }

  static const _styleUri = 'mapbox://styles/mapbox/streets-v12';
  static const _minZoom = 12;
  static const _maxZoom = 17;

  bool _cancelled = false;
  DriveAssignment? _selectedAssignment;
  String? _enumeratorId;

  /// Issue #46: when true, the validator demotes fatals to warnings so any
  /// available map data passes through to the importer, regardless of
  /// source, format, or predefined limitations.
  bool unrestricted = false;

  void setUnrestricted({required bool value}) {
    unrestricted = value;
  }

  Future<void> start() async {
    _cancelled = false;
    state = const DiscoveringAssignments();

    List<DriveAssignment> rawAssignments;
    try {
      rawAssignments = await _activeSource.listAssignments();
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

    // Show spinner immediately so the user sees feedback within one frame.
    state = const PreparingDownload();

    final selected =
        s.assignments.firstWhere((a) => a.assignmentId == s.selectedId);
    _selectedAssignment = selected;

    // Delta skip — already imported, go straight to tile download.
    // Still refresh the field_requirements.txt sidecar: Drive doesn't
    // reliably bump folder.modifiedTime when only a small sidecar is
    // added, so without this pull a freshly-dropped requirements file
    // would never reach the form layer on an already-imported folder.
    if (selected.alreadyDownloaded) {
      _enumeratorId = await googleAuthRepo.getEnumeratorId();
      if (!mounted) return;
      await _refreshFieldRequirementsSidecar(selected.assignmentId);
      if (!mounted) return;
      await _startTileDownload();
      return;
    }

    // Storage pre-check. getTotalSize hits the network for the FTP
    // transport — wrap so a transient socket/auth/path failure routes to
    // the retry path instead of bubbling out and stranding the user in
    // PreparingDownload.
    final int needed;
    try {
      needed = await _activeSource.getTotalSize(selected.assignmentId);
    } catch (e) {
      if (!mounted) return;
      state = GetMapsError(NetworkFailure(e.toString()), isRetryable: true);
      return;
    }
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
    final int needed;
    try {
      needed = await _activeSource.getTotalSize(selected.assignmentId);
    } catch (e) {
      if (!mounted) return;
      state = GetMapsError(NetworkFailure(e.toString()), isRetryable: true);
      return;
    }
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
          in _activeSource.downloadShapefiles(selected.assignmentId)) {
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

    // Issue #43 (post-review): if a `field_requirements.txt` rode along
    // with the shapefile, persist it locally and refresh the form-layer
    // cache. Done before validation so the .txt never feeds into the
    // shapefile rules (FileSetRule would otherwise flag it as extra).
    final configKey = shapefiles.keys.firstWhere(
      (k) => k.toLowerCase() == fieldRequirementsFilename,
      orElse: () => '',
    );
    if (configKey.isNotEmpty) {
      final bytes = shapefiles.remove(configKey);
      shapeMd5s.remove(configKey);
      if (bytes != null) await _persistFieldRequirements(bytes);
    }

    state = const ValidatingShapefiles();
    final report = validator.validate(
      shapefiles,
      shapeMd5s,
      relaxedMode: unrestricted,
    );

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

  Future<void> _persistFieldRequirements(Uint8List bytes) async {
    try {
      await writeFieldRequirements(bytes);
      onRequirementsUpdated?.call();
    } catch (_) {
      // Non-fatal — the form falls back to the bundled asset.
    }
  }

  Future<void> _refreshFieldRequirementsSidecar(String assignmentId) async {
    try {
      final bytes = await _activeSource.fetchFieldRequirementsSidecar(assignmentId);
      if (bytes != null) await _persistFieldRequirements(bytes);
    } catch (_) {
      // Non-fatal — keep moving to the tile download.
    }
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
    onRequirementsUpdated: () =>
        ref.read(fieldRequirementsRevisionProvider.notifier).state++,
  );
});

final currentAssignmentProvider = StreamProvider<Assignment?>((ref) {
  return ref.watch(assignmentRepositoryProvider).watchCurrentAssignment();
});
