import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:firecheck/core/db/database.dart';

typedef TriggerSync = Future<void> Function();

class RetryDeadUseCase {
  RetryDeadUseCase({required this.db, required this.triggerNow});
  final AppDatabase db;
  final TriggerSync triggerNow;

  Future<void> retryOne(String jobId) => _retry(jobId);

  Future<void> retryAll() => _retry(null);

  Future<void> _retry(String? jobId) async {
    await db.customUpdate(
      """
      UPDATE sync_jobs SET status='pending', attempts=0, last_error=NULL, next_retry_at=NULL
      WHERE status='dead' AND (? IS NULL OR id=?)
        AND NOT (entity_type='attribution_upload' AND EXISTS (
          SELECT 1 FROM sync_jobs newer
          WHERE newer.entity_type=sync_jobs.entity_type AND newer.entity_id=sync_jobs.entity_id
            AND newer.rowid > sync_jobs.rowid AND newer.status='success'
        ))""",
      variables: [Variable<String>(jobId), Variable<String>(jobId)],
      updates: {db.syncJobs},
    );
    await triggerNow();
  }
}
