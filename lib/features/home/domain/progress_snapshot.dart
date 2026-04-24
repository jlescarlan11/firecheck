class ProgressSnapshot {
  const ProgressSnapshot({
    required this.totalFeatures,
    required this.completedFeatures,
    required this.inProgressFeatures,
    required this.queuedJobs,
    required this.failedJobs,
    required this.deadJobs,
  });

  final int totalFeatures;
  final int completedFeatures;
  final int inProgressFeatures;
  final int queuedJobs;
  final int failedJobs;
  final int deadJobs;

  static const empty = ProgressSnapshot(
    totalFeatures: 0,
    completedFeatures: 0,
    inProgressFeatures: 0,
    queuedJobs: 0,
    failedJobs: 0,
    deadJobs: 0,
  );
}
