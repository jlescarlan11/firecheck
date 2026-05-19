/// String constants used in sync_jobs.entity_type.
///
/// All upload paths route through the conflict / dedup-aware RPCs:
///   - attributionUpload     → submit_attribution_with_conflict_check
///   - attributionResolve    → resolve_attribution
///   - newFeatureUpload      → submit_new_feature_with_dedup_check
///   - newFeatureResolve     → resolve_new_feature
class SyncEntityType {
  SyncEntityType._();
  static const photo = 'photo';
  static const featureGeometryUpdate = 'feature_geometry_update';

  static const attributionUpload = 'attribution_upload';
  static const attributionResolve = 'attribution_resolve';
  static const newFeatureUpload = 'new_feature_upload';
  static const newFeatureResolve = 'new_feature_resolve';
}
