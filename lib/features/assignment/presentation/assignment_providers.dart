// lib/features/assignment/presentation/assignment_providers.dart
import 'dart:async';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/device/storage_checker.dart';
import 'package:firecheck/core/drive/drive_api.dart';
import 'package:firecheck/core/drive/ftp_credentials.dart';
import 'package:firecheck/core/drive/transport_source.dart';
import 'package:firecheck/core/drive/transport_source_factory.dart';
import 'package:firecheck/core/forms/field_requirements_providers.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/mapbox/offline_pack_adapter.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_importer.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_validator.dart';
import 'package:firecheck/core/validation/validation_failure_reporter.dart';
import 'package:firecheck/features/assignment/data/assignment_name_resolver.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:firecheck/features/assignment/data/canonical_feature_publisher.dart';
import 'package:firecheck/features/assignment/data/feature_submission_status.dart';
import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/features/assignment/data/offline_tile_pack_repository.dart';
import 'package:firecheck/features/assignment/domain/get_maps_state.dart';
import 'package:firecheck/features/assignment/domain/shapefile_acquisition_use_case.dart';
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
    required ShapefileImporter shapefileImporter,
    required this.storageChecker,
    required ShapefileValidator validator,
    required ValidationFailureReporter reporter,
    this.onRequirementsUpdated,
    AssignmentNameResolver? assignmentNameResolver,
    CanonicalFeaturePublisher? canonicalFeaturePublisher,
    TransportSourceFactory? transportFactory,
    ShapefileAcquisitionUseCase? acquisitionUseCase,
  })  : _transportFactory =
            transportFactory ?? TransportSourceFactory(driveApi: driveApi),
        _useCase = acquisitionUseCase ??
            ShapefileAcquisitionUseCase(
              shapefileImporter: shapefileImporter,
              validator: validator,
              reporter: reporter,
              assignmentNameResolver: assignmentNameResolver,
              canonicalFeaturePublisher: canonicalFeaturePublisher,
              onRequirementsUpdated: onRequirementsUpdated,
            ),
        super(const Idle());

  /// Invoked after a freshly downloaded `field_requirements.txt` is
  /// written to local storage so the form layer re-reads it. Optional so
  /// tests can construct the notifier without a Riverpod ref.
  final void Function()? onRequirementsUpdated;

  final AssignmentRepository assignmentRepo;
  final OfflineTilePackRepository packRepo;
  final OfflinePackAdapter packAdapter;
  final FeatureRepository featureRepo;
  final DriveApi driveApi;
  final GoogleTokenSource googleAuthRepo;
  final StorageChecker storageChecker;

  final TransportSourceFactory _transportFactory;
  final ShapefileAcquisitionUseCase _useCase;

  /// Active map-source transport (Issue #45). Defaults to Google Drive
  /// (which uses the injected [driveApi]). When FTP is selected the
  /// factory builds an FTP source on the fly from the supplied
  /// credentials.
  TransportSource _transport = TransportSource.googleDrive;
  FtpCredentials? _ftpCredentials;

  void setTransport(TransportSource transport, {FtpCredentials? ftp}) {
    _transport = transport;
    _ftpCredentials = ftp;
  }

  DriveApi get _activeSource =>
      _transportFactory.resolve(_transport, ftp: _ftpCredentials);

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

    // Resolve the transport once. The factory throws if FTP credentials
    // are incomplete — route to a retryable error so the user can fix the
    // form and try again.
    final DriveApi source;
    try {
      source = _activeSource;
    } catch (e) {
      if (!mounted) return;
      state = GetMapsError(NetworkFailure(e.toString()), isRetryable: true);
      return;
    }

    // Delta skip — already imported, go straight to tile download.
    // Still refresh the field_requirements.txt sidecar: Drive doesn't
    // reliably bump folder.modifiedTime when only a small sidecar is
    // added, so without this pull a freshly-dropped requirements file
    // would never reach the form layer on an already-imported folder.
    if (selected.alreadyDownloaded) {
      _enumeratorId = await googleAuthRepo.getEnumeratorId();
      if (!mounted) return;
      await _useCase.refreshSidecar(
        source: source,
        assignmentId: selected.assignmentId,
      );
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
      needed = await source.getTotalSize(selected.assignmentId);
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
    await _runAcquisition(source: source, selected: selected, totalBytes: needed);
  }

  Future<void> acknowledgeWarning() async {
    final s = state;
    if (s is! ShapefileWarning) return;
    final selected = _selectedAssignment;
    if (selected == null) return;
    await _consume(
      _useCase.importPending(
        assignment: selected,
        enumeratorId: _enumeratorId ?? '',
        files: s.pendingFiles,
      ),
    );
  }

  Future<void> retryDownload() async {
    final s = state;
    if (s is! GetMapsError || !s.isRetryable) return;
    final selected = _selectedAssignment;
    if (selected == null) return;
    final DriveApi source;
    try {
      source = _activeSource;
    } catch (e) {
      if (!mounted) return;
      state = GetMapsError(NetworkFailure(e.toString()), isRetryable: true);
      return;
    }
    final int needed;
    try {
      needed = await source.getTotalSize(selected.assignmentId);
    } catch (e) {
      if (!mounted) return;
      state = GetMapsError(NetworkFailure(e.toString()), isRetryable: true);
      return;
    }
    await _runAcquisition(source: source, selected: selected, totalBytes: needed);
  }

  Future<void> _runAcquisition({
    required DriveApi source,
    required DriveAssignment selected,
    required int totalBytes,
  }) =>
      _consume(
        _useCase.acquire(
          source: source,
          assignment: selected,
          enumeratorId: _enumeratorId ?? '',
          totalBytes: totalBytes,
          unrestricted: unrestricted,
        ),
      );

  /// Maps [ShapefileAcquisitionEvent]s emitted by the use case onto
  /// [GetMapsState]. Terminal events ([AcquisitionImported],
  /// [AcquisitionImportFailed], [AcquisitionFailed], [AcquisitionWarning])
  /// end the consumption loop.
  Future<void> _consume(Stream<ShapefileAcquisitionEvent> stream) async {
    await for (final event in stream) {
      if (!mounted || _cancelled) return;
      switch (event) {
        case AcquisitionProgress(:final downloaded, :final total):
          state = DownloadingShapefiles(downloaded: downloaded, total: total);
        case AcquisitionValidating():
          state = const ValidatingShapefiles();
        case AcquisitionWarning(
            :final warnings,
            :final pendingFiles,
            :final expectedMd5s,
          ):
          state = ShapefileWarning(
            warnings: warnings,
            pendingFiles: pendingFiles,
            expectedMd5s: expectedMd5s,
          );
          return;
        case AcquisitionImporting():
          state = const ImportingShapefiles();
        case AcquisitionImported():
          if (!mounted) return;
          await _startTileDownload();
          return;
        case AcquisitionImportFailed():
          // Non-fatal — let the user open the map even if import failed.
          state = const Ready(featureCount: 0, totalBytes: 0);
          return;
        case AcquisitionFailed(:final failure, :final isRetryable):
          state = GetMapsError(failure, isRetryable: isRetryable);
          return;
      }
    }
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

/// Overridden in main.dart with SupabaseAssignmentNameResolver.
final assignmentNameResolverProvider = Provider<AssignmentNameResolver>((ref) {
  return const NoopAssignmentNameResolver();
});

/// Overridden in main.dart with SupabaseCanonicalFeaturePublisher.
final canonicalFeaturePublisherProvider =
    Provider<CanonicalFeaturePublisher>((ref) {
  return const NoopCanonicalFeaturePublisher();
});

final transportSourceFactoryProvider =
    Provider<TransportSourceFactory>((ref) {
  return TransportSourceFactory(driveApi: ref.watch(driveApiProvider));
});

final shapefileAcquisitionUseCaseProvider =
    Provider<ShapefileAcquisitionUseCase>((ref) {
  return ShapefileAcquisitionUseCase(
    shapefileImporter: ref.watch(shapefileImporterProvider),
    validator: ref.watch(shapefileValidatorProvider),
    reporter: ref.watch(validationFailureReporterProvider),
    assignmentNameResolver: ref.watch(assignmentNameResolverProvider),
    canonicalFeaturePublisher: ref.watch(canonicalFeaturePublisherProvider),
    onRequirementsUpdated: () =>
        ref.read(fieldRequirementsRevisionProvider.notifier).state++,
  );
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
    transportFactory: ref.watch(transportSourceFactoryProvider),
    acquisitionUseCase: ref.watch(shapefileAcquisitionUseCaseProvider),
  );
});

final currentAssignmentProvider = StreamProvider<Assignment?>((ref) {
  return ref.watch(assignmentRepositoryProvider).watchCurrentAssignment();
});

final featureSubmissionStatusResolverProvider =
    Provider<FeatureSubmissionStatusResolver>((ref) {
  return FeatureSubmissionStatusResolver(ref.watch(appDatabaseProvider));
});

/// Per-feature submission status for the current assignment. UI consumes
/// this to badge feature list entries / map markers as
/// unsurveyed / draft / pendingUpload / submittedByMe / submittedByOther
/// / needsResolution. Empty map while the assignment is loading.
final featureSubmissionStatusProvider =
    StreamProvider<Map<String, FeatureSubmissionStatus>>((ref) {
  final assignment = ref.watch(currentAssignmentProvider).value;
  if (assignment == null) {
    return Stream.value(const <String, FeatureSubmissionStatus>{});
  }
  final userId = ref.watch(currentUserIdProvider);
  return ref.watch(featureSubmissionStatusResolverProvider).watchByAssignment(
        assignmentId: assignment.id,
        currentUserId: userId,
      );
});
