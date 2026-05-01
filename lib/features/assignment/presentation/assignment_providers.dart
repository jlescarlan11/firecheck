// lib/features/assignment/presentation/assignment_providers.dart
import 'dart:typed_data';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/device/storage_checker.dart';
import 'package:firecheck/core/drive/drive_api.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/mapbox/offline_pack_adapter.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_importer.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:firecheck/features/assignment/data/offline_tile_pack_repository.dart';
import 'package:firecheck/features/assignment/domain/get_maps_state.dart';
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:firecheck/features/auth/presentation/google_auth_providers.dart';
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
  }) : super(const Idle());

  final AssignmentRepository assignmentRepo;
  final OfflineTilePackRepository packRepo;
  final OfflinePackAdapter packAdapter;
  final FeatureRepository featureRepo;
  final DriveApi driveApi;
  final GoogleAuthRepository googleAuthRepo;
  final ShapefileImporter shapefileImporter;
  final StorageChecker storageChecker;

  static const _styleUri = 'mapbox://styles/mapbox/streets-v12';
  static const _minZoom = 12;
  static const _maxZoom = 17;

  bool _cancelled = false;

  Future<void> start() async {
    _cancelled = false;
    state = const DiscoveringAssignments();

    List<DriveAssignment> rawAssignments;
    try {
      rawAssignments = await driveApi.listAssignments();
    } catch (e) {
      if (!mounted) return;
      state = GetMapsError(NetworkFailure(e.toString()));
      return;
    }

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

    final selected =
        s.assignments.firstWhere((a) => a.assignmentId == s.selectedId);

    // Storage pre-check (skip for already-downloaded)
    if (!selected.alreadyDownloaded) {
      final needed = await driveApi.getInputZipSize(selected.assignmentId);
      final available = await storageChecker.getAvailableBytes();
      if (available < needed) {
        if (!mounted) return;
        state = InsufficientStorage(
            requiredBytes: needed, availableBytes: available);
        return;
      }
    }

    // Delta skip — already imported, go straight to tile download
    if (selected.alreadyDownloaded) {
      await _startTileDownload();
      return;
    }

    // Download shapefiles
    if (!mounted) return;
    final needed = await driveApi.getInputZipSize(selected.assignmentId);
    state = DownloadingShapefiles(downloaded: 0, total: needed);
    List<int>? zipBytes;

    try {
      await for (final event
          in driveApi.downloadInputZip(selected.assignmentId)) {
        if (_cancelled || !mounted) return;
        switch (event) {
          case DriveDownloadProgress(:final downloaded, :final total):
            state =
                DownloadingShapefiles(downloaded: downloaded, total: total);
          case DriveDownloadComplete(:final bytes):
            zipBytes = bytes;
        }
      }
    } catch (e) {
      if (!mounted) return;
      state = GetMapsError(NetworkFailure(e.toString()));
      return;
    }

    if (_cancelled || !mounted) return;
    if (zipBytes == null) {
      state = const GetMapsError(
          NetworkFailure('Download completed with no data'));
      return;
    }

    // Import shapefiles
    state = const ImportingShapefiles();
    try {
      final enumeratorId = await googleAuthRepo.getEnumeratorId();
      await shapefileImporter.importInputZip(
        Uint8List.fromList(zipBytes),
        selected.assignmentId,
        selected.inputZipModifiedTime,
        selected.driveFolderId,
        enumeratorId,
      );
    } on ShapefileValidationFailure catch (f) {
      if (!mounted) return;
      state = GetMapsError(f);
      return;
    } catch (e) {
      if (!mounted) return;
      state = GetMapsError(StorageFailure(e.toString()));
      return;
    }

    await _startTileDownload();
  }

  Future<void> _startTileDownload() async {
    if (!mounted) return;
    final assignment = await assignmentRepo.getCurrentAssignment();
    if (!mounted) return;
    if (assignment == null) {
      state = const GetMapsError(
          StorageFailure('Assignment not found after import'));
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
            state = GetMapsError(StorageFailure(message));
            return;
        }
      }
    } on Object catch (e) {
      if (!mounted) return;
      state = GetMapsError(StorageFailure(e.toString()));
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
    state = const Idle();
  }
}

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
  );
});

final currentAssignmentProvider = StreamProvider<Assignment?>((ref) {
  return ref.watch(assignmentRepositoryProvider).watchCurrentAssignment();
});
