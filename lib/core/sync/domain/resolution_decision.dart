/// Decisions the user can pick at the conflict review screen.
/// Maps to `resolve_attribution(decision text)` on the server.
enum AttributionDecision {
  /// Drop the local pending row; the prior canonical (theirs) wins.
  keepTheirs('keep_theirs'),

  /// Supersede the prior canonical with the local row; audit it.
  forceOverwrite('force_overwrite');

  const AttributionDecision(this.wire);
  final String wire;
}

/// Decisions the user can pick at the new-feature dedup review screen.
/// Maps to `resolve_new_feature(decision text)` on the server.
enum DedupDecision {
  /// Both rows coexist as separate features. Just mark them reviewed.
  keepBoth('keep_both'),

  /// Supersede the older feature with this one; audit.
  replaceTheirs('replace_theirs'),

  /// Soft-delete the local pending feature; audit.
  discardMine('discard_mine');

  const DedupDecision(this.wire);
  final String wire;
}
