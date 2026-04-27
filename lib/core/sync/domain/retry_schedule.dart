/// Returns the wall-clock time at which a failed sync_job should be retried,
/// or null if the job has exhausted its retries (treat as dead).
///
/// Schedule per master spec §7: 30s, 2m, 10m, 1h, dead.
DateTime? nextRetryAt(int attempts, {DateTime? now}) {
  final base = now ?? DateTime.now();
  return switch (attempts) {
    1 => base.add(const Duration(seconds: 30)),
    2 => base.add(const Duration(minutes: 2)),
    3 => base.add(const Duration(minutes: 10)),
    4 => base.add(const Duration(hours: 1)),
    _ => null,
  };
}
