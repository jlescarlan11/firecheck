import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/realtime_subscriber.dart';
import 'package:firecheck/core/sync/data/remote_attributions_cache_repository.dart';
import 'package:firecheck/core/sync/data/remote_attributions_pull_service.dart';
import 'package:firecheck/core/sync/data/remote_cache_api.dart';
import 'package:firecheck/core/sync/worker/realtime_sync_controller.dart';
import 'package:firecheck/core/sync/worker/realtime_wiring.dart';
import 'package:firecheck/core/sync/worker/remote_cache_controller.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

final remoteAttributionsCacheRepositoryProvider =
    Provider<RemoteAttributionsCacheRepository>((ref) {
  return RemoteAttributionsCacheRepository(ref.watch(appDatabaseProvider));
});

final remoteCacheApiProvider = Provider<RemoteCacheApi>((ref) {
  return SupabaseRemoteCacheApi(Supabase.instance.client);
});

final remoteAttributionsPullServiceProvider =
    Provider<RemoteAttributionsPullService>((ref) {
  return RemoteAttributionsPullService(
    api: ref.watch(remoteCacheApiProvider),
    cache: ref.watch(remoteAttributionsCacheRepositoryProvider),
  );
});

final remoteCacheControllerProvider =
    Provider<RemoteCacheController>((ref) {
  final controller = RemoteCacheController(
    pullService: ref.watch(remoteAttributionsPullServiceProvider),
    db: ref.watch(appDatabaseProvider),
  );
  ref.onDispose(controller.stop);
  return controller;
});

final realtimeSubscriberProvider = Provider<RealtimeSubscriber>((ref) {
  return SupabaseRealtimeSubscriber(Supabase.instance.client);
});

final realtimeSyncControllerProvider =
    Provider<RealtimeSyncController>((ref) {
  final controller = RealtimeSyncController(
    subscriber: ref.watch(realtimeSubscriberProvider),
    pullService: ref.watch(remoteAttributionsPullServiceProvider),
    db: ref.watch(appDatabaseProvider),
  );
  ref.onDispose(controller.stop);
  return controller;
});

final realtimeWiringProvider = Provider<RealtimeWiring>((ref) {
  final wiring = RealtimeWiring(
    controller: ref.watch(realtimeSyncControllerProvider),
  );
  ref.onDispose(wiring.dispose);
  return wiring;
});

/// Live stream of canonical remote attributions for an assignment.
/// Phase-4 badge UI watches this.
final remoteAttributionsForAssignmentProvider =
    StreamProvider.family<List<RemoteAttributionsCacheData>, String>(
  (ref, assignmentId) {
    final db = ref.watch(appDatabaseProvider);
    return (db.select(db.remoteAttributionsCache)
          ..where((t) =>
              t.assignmentId.equals(assignmentId) &
              t.supersededAt.isNull(),))
        .watch();
  },
);

/// Live stream of canonical remote new features for an assignment.
final remoteNewFeaturesForAssignmentProvider =
    StreamProvider.family<List<RemoteNewFeaturesCacheData>, String>(
  (ref, assignmentId) {
    final db = ref.watch(appDatabaseProvider);
    return (db.select(db.remoteNewFeaturesCache)
          ..where((t) =>
              t.assignmentId.equals(assignmentId) &
              t.supersededAt.isNull(),))
        .watch();
  },
);
