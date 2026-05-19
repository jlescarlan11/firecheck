import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/domain/resolution_decision.dart';
import 'package:firecheck/core/sync/domain/submission_sync_status.dart';
import 'package:firecheck/core/sync/domain/sync_entity_type.dart';
import 'package:firecheck/core/sync/domain/sync_job_status.dart';
import 'package:uuid/uuid.dart';

/// Stages a resolution decision: writes the chosen action into
/// `pending_resolutions` and enqueues a `*_resolve` sync_job so the
/// worker can call the corresponding RPC when online.
class ConflictReviewRepository {
  ConflictReviewRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  /// Streams local submissions parked in `awaiting_user_resolution`.
  /// The review list watches this.
  Stream<List<Submission>> watchAwaitingSubmissions() {
    return (_db.select(_db.submissions)
          ..where((t) => t.syncStatus
              .equals(SubmissionSyncStatus.awaitingUserResolution))
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.updatedAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .watch();
  }

  /// Streams local features parked in dedup review — i.e. the
  /// dedup-aware upload returned `dedup_pending` and the local row was
  /// flagged via `pendingDedupOf`. Cleared when the worker drains the
  /// matching `new_feature_resolve` sync_job.
  Stream<List<Feature>> watchPendingDedupFeatures() {
    return (_db.select(_db.features)
          ..where((t) => t.pendingDedupOf.isNotNull())
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .watch();
  }

  /// Commits a user's chosen attribution decision. Writes the row to
  /// `pending_resolutions` (so the worker has the decision when it
  /// runs) and enqueues an `attribution_resolve` sync_job.
  ///
  /// Idempotent: re-running with the same submissionId overwrites the
  /// queued decision (user changed their mind before the worker ran).
  /// "Skip" is *not* this method — skip simply doesn't write anything.
  Future<void> queueAttributionDecision({
    required String submissionId,
    required AttributionDecision decision,
    String? resolutionNote,
  }) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db.into(_db.pendingResolutions).insertOnConflictUpdate(
            PendingResolutionsCompanion(
              targetId: Value(submissionId),
              kind: const Value('attribution'),
              decision: Value(decision.wire),
              resolutionNote: Value(resolutionNote),
              createdAt: Value(now),
            ),
          );
      final existing = await (_db.select(_db.syncJobs)
            ..where((t) =>
                t.entityType.equals(SyncEntityType.attributionResolve) &
                t.entityId.equals(submissionId),))
          .getSingleOrNull();
      if (existing == null) {
        await _db.into(_db.syncJobs).insert(
              SyncJobsCompanion.insert(
                id: _uuid.v4(),
                entityType: SyncEntityType.attributionResolve,
                entityId: submissionId,
                createdAt: now,
              ),
            );
      } else {
        // Wake the job back up if it had previously errored.
        await (_db.update(_db.syncJobs)
              ..where((t) => t.id.equals(existing.id)))
            .write(
          const SyncJobsCompanion(
            status: Value(SyncJobStatus.pending),
            attempts: Value(0),
            lastError: Value(null),
            nextRetryAt: Value(null),
          ),
        );
      }
    });
  }

  Future<void> queueDedupDecision({
    required String featureId,
    required DedupDecision decision,
    String? resolutionNote,
  }) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db.into(_db.pendingResolutions).insertOnConflictUpdate(
            PendingResolutionsCompanion(
              targetId: Value(featureId),
              kind: const Value('new_feature'),
              decision: Value(decision.wire),
              resolutionNote: Value(resolutionNote),
              createdAt: Value(now),
            ),
          );
      final existing = await (_db.select(_db.syncJobs)
            ..where((t) =>
                t.entityType.equals(SyncEntityType.newFeatureResolve) &
                t.entityId.equals(featureId),))
          .getSingleOrNull();
      if (existing == null) {
        await _db.into(_db.syncJobs).insert(
              SyncJobsCompanion.insert(
                id: _uuid.v4(),
                entityType: SyncEntityType.newFeatureResolve,
                entityId: featureId,
                createdAt: now,
              ),
            );
      } else {
        await (_db.update(_db.syncJobs)
              ..where((t) => t.id.equals(existing.id)))
            .write(
          const SyncJobsCompanion(
            status: Value(SyncJobStatus.pending),
            attempts: Value(0),
            lastError: Value(null),
            nextRetryAt: Value(null),
          ),
        );
      }
    });
  }
}
