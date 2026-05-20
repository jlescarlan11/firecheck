import 'package:firecheck/core/sync/presentation/sync_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streams the user-facing lock state for the current assignment by
/// combining the assignments row (submittedAt, closedRemotely) with a
/// lazily-generated bundle file for the closed-remotely path.
final assignmentLockStateProvider =
    StreamProvider<AssignmentLockState>((ref) async* {
  final repo = ref.watch(assignmentRepositoryProvider);
  final bundle = ref.watch(pendingWorkBundleProvider);

  await for (final assignment in repo.watchCurrentAssignment()) {
    if (assignment == null) {
      yield const Unlocked();
      continue;
    }
    if (assignment.closedRemotely) {
      yield const ClosedRemotely(bundleFile: null);
      try {
        final file = await bundle.exportFor(assignment.id);
        yield ClosedRemotely(bundleFile: file);
      } on Object {
        // Bundle export is best-effort; the blocker UI degrades gracefully
        // when bundleFile is null.
      }
    } else if (assignment.submittedAt != null) {
      yield Submitted(submittedAt: assignment.submittedAt!);
    } else {
      yield const Unlocked();
    }
  }
});

/// Convenience: synchronous bool that consumers can watch to gate
/// edit-affordances. True means edits should be blocked.
///
/// Submitted is no longer a hard lock — enumerators submit progressively
/// (partial batches), and the existing supersede flow on the server
/// (submit_attribution_with_conflict_check) handles re-submission of an
/// already-submitted feature cleanly. Only ClosedRemotely (admin closed
/// the assignment) actually blocks edits.
final isAssignmentLockedProvider = Provider<bool>((ref) {
  final state = ref.watch(assignmentLockStateProvider).value;
  return state is ClosedRemotely;
});
