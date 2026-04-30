import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/mapbox/offline_pack_adapter.dart';
import 'package:firecheck/core/supabase/supabase_client_provider.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:firecheck/features/assignment/data/offline_tile_pack_repository.dart';
import 'package:firecheck/features/assignment/domain/get_maps_state.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/map/data/feature_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

final assignmentRepositoryProvider = Provider<AssignmentRepository>((ref) {
  return AssignmentRepository(
    client: ref.watch(supabaseClientProvider),
    db: ref.watch(appDatabaseProvider),
  );
});

final offlineTilePackRepositoryProvider =
    Provider<OfflineTilePackRepository>((ref) {
  return OfflineTilePackRepository(ref.watch(appDatabaseProvider));
});

/// Defaults to the [FakeOfflinePackAdapter] with no events.
/// `main.dart` overrides this to use [MapboxOfflinePackAdapter] backed by a
/// real `TileStore` instance (see T19).
final offlinePackAdapterProvider = Provider<OfflinePackAdapter>((ref) {
  return FakeOfflinePackAdapter();
});

final featureRepositoryProvider = Provider<FeatureRepository>((ref) {
  return FeatureRepository(ref.watch(appDatabaseProvider));
});

class GetMapsNotifier extends StateNotifier<GetMapsState> {
  GetMapsNotifier({
    required this.assignmentRepo,
    required this.packRepo,
    required this.packAdapter,
    required this.featureRepo,
  }) : super(const Idle());

  final AssignmentRepository assignmentRepo;
  final OfflineTilePackRepository packRepo;
  final OfflinePackAdapter packAdapter;
  final FeatureRepository featureRepo;

  static const _styleUri = 'mapbox://styles/mapbox/streets-v12';
  static const _minZoom = 12;
  static const _maxZoom = 17;

  Future<void> start() async {
    state = const FetchingFeatures();
    try {
      // TODO(US-17 T17): Rewrite GetMapsNotifier to use Drive + shapefile fetch
      // instead of fetchAndUpsertCurrent. For now, this will be implemented
      // when T17 refactors the entire Get Maps flow.
      // await assignmentRepo.fetchAndUpsertCurrent();
    } on Failure catch (f) {
      state = GetMapsError(f);
      return;
    } on Object catch (e) {
      state = GetMapsError(StorageFailure(e.toString()));
      return;
    }

    final assignment = await assignmentRepo.getCurrentAssignment();
    if (assignment == null) {
      state = const GetMapsError(
        ServerRejectedFailure('No assignment after fetch', 500),
      );
      return;
    }

    final packId = const Uuid().v4();
    await packRepo.upsert(
      id: packId,
      assignmentId: assignment.id,
      regionBoundsGeojson: assignment.boundaryPolygonGeojson,
    );

    state = const DownloadingTiles(downloadedBytes: 0, totalBytes: 0);

    final stream = packAdapter.createPack(
      regionGeojson: assignment.boundaryPolygonGeojson,
      styleUri: _styleUri,
      minZoom: _minZoom,
      maxZoom: _maxZoom,
    );

    try {
      await for (final event in stream) {
        switch (event) {
          case OfflinePackProgress(:final downloaded, :final total):
            state = DownloadingTiles(
              downloadedBytes: downloaded,
              totalBytes: total,
            );
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
              featureCount: features.length,
              totalBytes: currentTotal,
            );
            return;
          case OfflinePackError(:final message):
            await packRepo.markError(packId, message);
            state = GetMapsError(StorageFailure(message));
            return;
        }
      }
    } on Object catch (e) {
      state = GetMapsError(StorageFailure(e.toString()));
    }
  }

  Future<void> cancel() async {
    await packAdapter.cancelAllPacks();
    state = const Cancelled();
  }

  void reset() {
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
  );
});

/// Reactive "current assignment" for the home screen and map.
final currentAssignmentProvider = StreamProvider<Assignment?>((ref) {
  return ref.watch(assignmentRepositoryProvider).watchCurrentAssignment();
});
