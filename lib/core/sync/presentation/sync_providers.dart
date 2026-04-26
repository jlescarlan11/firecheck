import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:firecheck/core/sync/data/supabase_sync_api.dart';
import 'package:firecheck/core/sync/data/sync_api.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
import 'package:firecheck/core/sync/failure/assignment_lock_repository.dart';
import 'package:firecheck/core/sync/failure/pending_work_bundle.dart';
import 'package:firecheck/core/sync/worker/sync_controller.dart';
import 'package:firecheck/core/sync/worker/sync_worker.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

final syncApiProvider = Provider<SyncApi>((ref) {
  return SupabaseSyncApi(Supabase.instance.client);
});

final syncJobsRepositoryProvider = Provider<SyncJobsRepository>((ref) {
  return SyncJobsRepository(ref.watch(appDatabaseProvider));
});

final assignmentLockRepositoryProvider =
    Provider<AssignmentLockRepository>((ref) {
  return AssignmentLockRepository(ref.watch(appDatabaseProvider));
});

final pendingWorkBundleProvider = Provider<PendingWorkBundle>((ref) {
  return PendingWorkBundle(ref.watch(appDatabaseProvider));
});

final syncWorkerProvider = Provider<SyncWorker>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SyncWorker(
    api: ref.watch(syncApiProvider),
    jobs: ref.watch(syncJobsRepositoryProvider),
    payload: SubmissionPayloadBuilder(db),
    lock: ref.watch(assignmentLockRepositoryProvider),
    db: db,
    bundle: ref.watch(pendingWorkBundleProvider),
  );
});

final syncControllerProvider = Provider<SyncController>((ref) {
  final controller = SyncController(ref.watch(syncWorkerProvider));
  ref.onDispose(controller.stop);
  return controller;
});
