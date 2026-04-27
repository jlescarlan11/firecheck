import 'package:flutter/foundation.dart';

/// Drives the Review screen's render mode.
///
/// Idle             → show summary + validation + start button
/// InProgress       → swap to progress bar + collapsible per-item list
/// Completed        → success snackbar + transition to Locked (if 0 failed)
///                    or stay on Failed Jobs section (if >0 failed)
/// Locked           → screen unmounts; consumer routes back to Home
sealed class UploadProgress {
  const UploadProgress();
}

@immutable
class Idle extends UploadProgress {
  const Idle();
}

@immutable
class InProgress extends UploadProgress {
  const InProgress({required this.done, required this.total});
  final int done;
  final int total;

  @override
  bool operator ==(Object other) =>
      other is InProgress && other.done == done && other.total == total;
  @override
  int get hashCode => Object.hash(done, total);
}

@immutable
class Completed extends UploadProgress {
  const Completed({required this.failedCount});
  final int failedCount;

  @override
  bool operator ==(Object other) =>
      other is Completed && other.failedCount == failedCount;
  @override
  int get hashCode => failedCount.hashCode;
}

@immutable
class Locked extends UploadProgress {
  const Locked({required this.kind, this.submittedAt});
  final LockKind kind;
  final DateTime? submittedAt;

  @override
  bool operator ==(Object other) =>
      other is Locked && other.kind == kind && other.submittedAt == submittedAt;
  @override
  int get hashCode => Object.hash(kind, submittedAt);
}

enum LockKind { submitted, closedRemotely }
