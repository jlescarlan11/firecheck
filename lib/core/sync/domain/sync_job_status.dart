/// String constants used in sync_jobs.status.
/// Lifecycle: pending → in_progress → success | failed | dead
class SyncJobStatus {
  SyncJobStatus._();
  static const pending = 'pending';
  static const inProgress = 'in_progress';
  static const success = 'success';
  static const failed = 'failed';
  static const dead = 'dead';
}
