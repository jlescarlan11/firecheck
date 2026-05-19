/// String constants used in `submissions.sync_status` (Drift + Supabase).
///
/// Lifecycle:
///   draft (form open / partial) → queued (Finish tapped) → uploaded
///                                                       ↘ awaitingUserResolution (conflict)
///                                                             ↘ uploaded (force_overwrite)
///                                                             ↘ withdrawn (keep_theirs / discard_mine)
class SubmissionSyncStatus {
  SubmissionSyncStatus._();
  static const draft = 'draft';
  static const inProgress = 'in_progress';
  static const queued = 'queued';
  static const uploaded = 'uploaded';

  /// Server returned `conflict` or `dedup_pending` for this submission;
  /// the row sits parked until the user picks a side in the review UI.
  static const awaitingUserResolution = 'awaiting_user_resolution';

  /// User chose "keep theirs" / "discard mine" — the local row is
  /// effectively cancelled. Kept for audit; never re-uploaded.
  static const withdrawn = 'withdrawn';
}
