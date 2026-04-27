import 'dart:io';

import 'package:flutter/foundation.dart';

/// User-facing lock state for the current assignment.
///
/// Closed-remotely overrides Submitted. (Phase 4b accepts that the
/// closed_remotely flag may flip after a successful submit; the user is
/// blocked regardless.)
sealed class AssignmentLockState {
  const AssignmentLockState();
}

@immutable
class Unlocked extends AssignmentLockState {
  const Unlocked();

  @override
  bool operator ==(Object other) => other is Unlocked;
  @override
  int get hashCode => 0;
}

@immutable
class Submitted extends AssignmentLockState {
  const Submitted({required this.submittedAt});
  final DateTime submittedAt;

  @override
  bool operator ==(Object other) =>
      other is Submitted && other.submittedAt == submittedAt;
  @override
  int get hashCode => submittedAt.hashCode;
}

@immutable
class ClosedRemotely extends AssignmentLockState {
  const ClosedRemotely({required this.bundleFile});
  final File? bundleFile; // may be null briefly while bundle is generating

  @override
  bool operator ==(Object other) =>
      other is ClosedRemotely && other.bundleFile?.path == bundleFile?.path;
  @override
  int get hashCode => bundleFile?.path.hashCode ?? 0;
}
