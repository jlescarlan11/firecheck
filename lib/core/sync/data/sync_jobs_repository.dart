import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/domain/sync_job_status.dart';

class SyncJobsRepository {
  SyncJobsRepository(this._db, {this.ownerId});
  final String? ownerId;
  final AppDatabase _db;

  /// Claims up to [n] pending sync_jobs ready to run NOW. Atomically transitions
  /// claimed rows to in_progress so concurrent invocations don't double-claim.
  ///
  /// Ordering: submission jobs first (so dependent photos can unblock), then
  /// remaining jobs by created_at ascending.
  Future<List<SyncJob>> claimUpToN(int n, {DateTime? now}) async {
    final cutoff = now ?? DateTime.now();
    return _db.transaction(() async {
      // Gate two interlocking conditions:
      //   1. Photo jobs that block on a submission wait for the local
      //      submission row to reach sync_status='uploaded'.
      //   2. Attribution upload jobs whose feature is new wait for the
      //      corresponding new-feature upload job to reach `success`.
      //      Otherwise the submission's feature_id FK fails on the
      //      server.
      final raw = await _db.customSelect(
        '''
        SELECT j.* FROM sync_jobs j
        WHERE (j.status = ? OR (j.status='in_progress' AND j.next_retry_at IS NOT NULL))
          AND (j.next_retry_at IS NULL OR j.next_retry_at <= ?)
          AND NOT (j.entity_type='attribution_upload' AND EXISTS (
            SELECT 1 FROM sync_jobs newer WHERE newer.entity_type=j.entity_type
              AND newer.entity_id=j.entity_id AND newer.rowid > j.rowid AND newer.status='success'
          ))
          AND NOT EXISTS (
            SELECT 1 FROM sync_jobs earlier
            WHERE earlier.entity_type=j.entity_type AND earlier.entity_id=j.entity_id
              AND earlier.rowid < j.rowid
              AND earlier.status NOT IN ('success', 'dead')
          )
          AND NOT EXISTS (
            SELECT 1 FROM assignments a JOIN features f ON f.assignment_id=a.id
            LEFT JOIN submissions s ON s.feature_id=f.id
            LEFT JOIN photos p ON p.submission_id=s.id
            LEFT JOIN feature_geometry_revisions g ON g.feature_id=f.id
            WHERE a.closed_remotely=1 AND (
              (j.entity_type LIKE 'attribution_%' AND s.id=j.entity_id) OR
              (j.entity_type LIKE 'new_feature_%' AND f.id=j.entity_id) OR
              (j.entity_type='photo' AND p.id=j.entity_id) OR
              (j.entity_type='feature_geometry_update' AND g.id=j.entity_id)
            )
          )
          AND (? IS NULL OR EXISTS (
            SELECT 1 FROM submissions owned
            LEFT JOIN photos photo ON photo.submission_id=owned.id
            WHERE owned.submitted_by=? AND (
              (j.entity_type LIKE 'attribution_%' AND j.entity_id=owned.id) OR
              (j.entity_type LIKE 'new_feature_%' AND j.entity_id=owned.feature_id) OR
              (j.entity_type='photo' AND j.entity_id=photo.id))
          ) OR (j.entity_type='feature_geometry_update' AND EXISTS (
            SELECT 1 FROM feature_geometry_revisions rev WHERE rev.id=j.entity_id AND rev.edited_by=?
          )))
          AND (
            j.blocks_on_submission_id IS NULL
            OR EXISTS (
              SELECT 1 FROM submissions s
              WHERE s.id = j.blocks_on_submission_id AND s.sync_status = 'uploaded'
            )
          )
          AND NOT (
            j.entity_type = 'attribution_upload'
            AND EXISTS (
              SELECT 1 FROM submissions s2
              JOIN features f2 ON f2.id = s2.feature_id
              WHERE s2.id = j.entity_id
                AND f2.is_new = 1
                AND NOT EXISTS (
                  SELECT 1 FROM sync_jobs nf
                  WHERE nf.entity_type = 'new_feature_upload'
                    AND nf.entity_id = f2.id
                    AND nf.status = 'success'
                )
            )
          )
        ORDER BY (
          CASE j.entity_type
            WHEN 'new_feature_upload'  THEN 0
            WHEN 'attribution_upload'  THEN 1
            ELSE                            2
          END
        ), j.created_at
        LIMIT ?
        ''',
        variables: [
          Variable.withString(SyncJobStatus.pending),
          Variable.withDateTime(cutoff),
          Variable<String>(ownerId),
          Variable<String>(ownerId),
          Variable<String>(ownerId),
          Variable.withInt(n),
        ],
        readsFrom: {_db.syncJobs, _db.submissions, _db.features},
      ).get();
      final claimed = raw.map((row) => _db.syncJobs.map(row.data)).toList();
      for (final j in claimed) {
        await (_db.update(_db.syncJobs)..where((t) => t.id.equals(j.id))).write(
          SyncJobsCompanion(
            status: const Value(SyncJobStatus.inProgress),
            nextRetryAt: Value(cutoff.add(const Duration(minutes: 10))),
          ),
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
    return _db
        .customSelect(
          'SELECT * FROM sync_jobs WHERE entity_type=? AND entity_id=? ORDER BY rowid DESC LIMIT 1',
          variables: [
            Variable.withString(entityType),
            Variable.withString(entityId),
          ],
          readsFrom: {_db.syncJobs},
        )
        .getSingleOrNull()
        .then((row) => row == null ? null : _db.syncJobs.map(row.data));
  }
}
