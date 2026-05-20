/// Terminal outcomes of [ExecuteAssignmentUploadUseCase.execute].
///
/// The use case orchestrates the full review-page upload pipeline:
/// confirmation gates → Supabase sync finalize → Drive enqueue/drain/
/// finalize. Each branch below corresponds to one place the pipeline
/// can settle; the screen pattern-matches on the result to render
/// success cards, snackbars, or no-ops.
sealed class UploadFlowOutcome {
  const UploadFlowOutcome();
}

/// No current assignment was loaded — the screen should silently no-op.
final class UploadFlowNoAssignment extends UploadFlowOutcome {
  const UploadFlowNoAssignment();
}

/// User declined one of the confirmation dialogs (partial / overwrite /
/// unverified). Nothing was uploaded.
final class UploadFlowCancelled extends UploadFlowOutcome {
  const UploadFlowCancelled(this.reason);
  final UploadFlowCancellationReason reason;
}

enum UploadFlowCancellationReason { partial, overwrite, unverified }

/// Supabase phase failed before Drive even started. The screen should
/// surface a snackbar; in-progress upload state has already been reset.
final class UploadFlowSupabaseFailed extends UploadFlowOutcome {
  const UploadFlowSupabaseFailed(this.error);
  final Object error;
}

/// Drive queue was empty — nothing to upload. Notifier is already set
/// to failure with `canRetry: false`.
final class UploadFlowEmpty extends UploadFlowOutcome {
  const UploadFlowEmpty();
}

/// Drive drain finished but some jobs failed/dead. Notifier carries the
/// human-readable message.
final class UploadFlowIncomplete extends UploadFlowOutcome {
  const UploadFlowIncomplete({
    required this.completedCount,
    required this.failedCount,
  });
  final int completedCount;
  final int failedCount;
}

/// Every Drive job completed and bookkeeping has been persisted.
final class UploadFlowSucceeded extends UploadFlowOutcome {
  const UploadFlowSucceeded({
    required this.folderPath,
    required this.confirmedAt,
  });
  final String folderPath;
  final DateTime confirmedAt;
}
