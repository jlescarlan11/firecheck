/// Server's response to `submit_attribution_with_conflict_check`,
/// translated into a sealed Dart type so the sync worker can pattern-match
/// without sniffing string keys.
sealed class SubmitAttributionResult {
  const SubmitAttributionResult();
}

/// The server accepted the submission as canonical. No prior canonical
/// existed, OR the user explicitly knew about it (`base_version_id`).
class AttributionCommitted extends SubmitAttributionResult {
  const AttributionCommitted(this.submissionId);
  final String submissionId;
}

/// The server already has a canonical row with identical typed values;
/// the upload was a no-op. The local row should be marked withdrawn.
class AttributionAgreedSkip extends SubmitAttributionResult {
  const AttributionAgreedSkip(this.canonicalSubmissionId);
  final String canonicalSubmissionId;
}

/// A real value conflict — both rows now exist on the server, with the
/// new one *not* superseding the old. The user must pick a side via the
/// review UI.
class AttributionConflict extends SubmitAttributionResult {
  const AttributionConflict({
    required this.pendingId,
    required this.theirSubmissionId,
  });
  final String pendingId;
  final String theirSubmissionId;
}

/// Server's response to `submit_new_feature_with_dedup_check`.
sealed class SubmitNewFeatureResult {
  const SubmitNewFeatureResult();
}

class NewFeatureCommitted extends SubmitNewFeatureResult {
  const NewFeatureCommitted(this.featureId);
  final String featureId;
}

class NewFeatureDedupPending extends SubmitNewFeatureResult {
  const NewFeatureDedupPending({
    required this.pendingId,
    required this.possibleDuplicateOf,
  });
  final String pendingId;
  final String possibleDuplicateOf;
}
