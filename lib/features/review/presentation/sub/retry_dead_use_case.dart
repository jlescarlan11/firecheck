import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:firecheck/core/db/database.dart';

typedef TriggerSync = Future<void> Function();

class RetryDeadUseCase {
  RetryDeadUseCase({required this.db, required this.triggerNow});
  final AppDatabase db;
  final TriggerSync triggerNow;

  Future<void> retryOne(String jobId) async {
    await (db.update(db.syncJobs)
          ..where((t) => t.id.equals(jobId) & t.status.equals('dead')))
        .write(const SyncJobsCompanion(
      status: Value('pending'),
      attempts: Value(0),
      lastError: Value(null),
      nextRetryAt: Value(null),
    ));
    await triggerNow();
  }

  Future<void> retryAll() async {
    await (db.update(db.syncJobs)..where((t) => t.status.equals('dead')))
        .write(const SyncJobsCompanion(
      status: Value('pending'),
      attempts: Value(0),
      lastError: Value(null),
      nextRetryAt: Value(null),
    ));
    await triggerNow();
  }
}
