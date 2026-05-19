/// String constants used in sync_jobs.entity_type.
///
/// The conflict/dedup-aware types route through their respective RPCs:
///   - attributionUpload     → submit_attribution_with_conflict_check
///   - attributionResolve    → resolve_attribution
///   - newFeatureUpload      → submit_new_feature_with_dedup_check
///   - newFeatureResolve     → resolve_new_feature
///
/// The legacy [submission] and [newFeature] types remain (and still work)
/// for one release as a fallback. New submissions enqueue under the new
/// types; the legacy code paths will be removed in a follow-up release.
class SyncEntityType {
  SyncEntityType._();
  static const submission = 'submission';
  static const photo = 'photo';
  static const newFeature = 'new_feature';
  static const featureGeometryUpdate = 'feature_geometry_update';

  // Multi-user attribution sync types.
  static const attributionUpload = 'attribution_upload';
  static const attributionResolve = 'attribution_resolve';
  static const newFeatureUpload = 'new_feature_upload';
  static const newFeatureResolve = 'new_feature_resolve';
}
