/// Outcome of attempting to sync a single sync_jobs row.
/// Maps from HTTP status:
///   2xx → Success
///   401 → AuthExpired (refresh token, retry once)
///   409 → AssignmentClosed (halt queue, export bundle)
///   4xx (other) → PermanentFailure (mark dead)
///   5xx / network / timeout → TransientFailure (retry per schedule)
sealed class SyncOutcome {
  const SyncOutcome();
}

class Success extends SyncOutcome {
  const Success();
}

class TransientFailure extends SyncOutcome {
  const TransientFailure(this.error);
  final String error;
}

class PermanentFailure extends SyncOutcome {
  const PermanentFailure(this.error);
  final String error;
}

class AuthExpired extends SyncOutcome {
  const AuthExpired();
}

class AssignmentClosed extends SyncOutcome {
  const AssignmentClosed(this.assignmentId);
  final String assignmentId;
}
