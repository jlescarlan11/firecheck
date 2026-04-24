import 'package:drift/drift.dart';

@TableIndex(name: 'sync_jobs_status_retry_idx', columns: {#status, #nextRetryAt})
class SyncJobs extends Table {
  TextColumn get id => text()();
  TextColumn get entityType =>
      text()(); // submission|photo|new_feature|status_update
  TextColumn get entityId => text()();
  TextColumn get status =>
      text().withDefault(const Constant('pending'))(); // pending|in_progress|success|failed|dead
  TextColumn get blocksOnSubmissionId => text().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
