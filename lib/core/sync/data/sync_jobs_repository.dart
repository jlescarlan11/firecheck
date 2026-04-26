import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/domain/sync_entity_type.dart';
import 'package:firecheck/core/sync/domain/sync_job_status.dart';

class SyncJobsRepository {
  SyncJobsRepository(this._db);
  final AppDatabase _db;

  /// Claims up to [n] pending sync_jobs ready to run NOW. Atomically transitions
  /// claimed rows to in_progress so concurrent invocations don't double-claim.
  ///
  /// Ordering: submission jobs first (so dependent photos can unblock), then
  /// remaining jobs by created_at ascending.
  Future<List<SyncJob>> claimUpToN(int n, {DateTime? now}) async {
    final cutoff = now ?? DateTime.now();
    return _db.transaction(() async {
      final raw = await _db.customSelect(
        '''
        SELECT j.* FROM sync_jobs j
        WHERE j.status = ?
          AND (j.next_retry_at IS NULL OR j.next_retry_at <= ?)
          AND (
            j.blocks_on_submission_id IS NULL
            OR EXISTS (
              SELECT 1 FROM submissions s
              WHERE s.id = j.blocks_on_submission_id AND s.sync_status = 'uploaded'
            )
          )
        ORDER BY (CASE WHEN j.entity_type = ? THEN 0 ELSE 1 END), j.created_at
        LIMIT ?
        ''',
        variables: [
          Variable.withString(SyncJobStatus.pending),
          Variable.withDateTime(cutoff),
          Variable.withString(SyncEntityType.submission),
          Variable.withInt(n),
        ],
        readsFrom: {_db.syncJobs, _db.submissions},
      ).get();
      final claimed = raw.map((row) => _db.syncJobs.map(row.data)).toList();
      for (final j in claimed) {
        await (_db.update(_db.syncJobs)..where((t) => t.id.equals(j.id))).write(
          const SyncJobsCompanion(status: Value(SyncJobStatus.inProgress)),
        );
      }
      return claimed;
    });
  }

  Future<void> markSuccess(String jobId) async {
    await (_db.update(_db.syncJobs)..where((t) => t.id.equals(jobId))).write(
      const SyncJobsCompanion(status: Value(SyncJobStatus.success)),
    );
  }

  Future<void> markPendingRetry(
    String jobId, {
    required int attempts,
    required String lastError,
    required DateTime? nextRetryAt,
  }) async {
    await (_db.update(_db.syncJobs)..where((t) => t.id.equals(jobId))).write(
      SyncJobsCompanion(
        status: const Value(SyncJobStatus.pending),
        attempts: Value(attempts),
        lastError: Value(lastError),
        nextRetryAt: Value(nextRetryAt),
      ),
    );
  }

  Future<void> markDead(
    String jobId, {
    required String error,
    required int attempts,
  }) async {
    await (_db.update(_db.syncJobs)..where((t) => t.id.equals(jobId))).write(
      SyncJobsCompanion(
        status: const Value(SyncJobStatus.dead),
        attempts: Value(attempts),
        lastError: Value(error),
      ),
    );
  }

  Future<SyncJob?> findByEntity(String entityType, String entityId) {
    return (_db.select(_db.syncJobs)
          ..where((t) =>
              t.entityType.equals(entityType) & t.entityId.equals(entityId),))
        .getSingleOrNull();
  }
}
