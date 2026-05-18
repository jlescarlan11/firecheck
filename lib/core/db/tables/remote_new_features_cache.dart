import 'package:drift/drift.dart';

/// Local mirror of remote `public.features` rows where `is_new = true`,
/// scoped to assignments the current user is a member of.
///
/// We store geometry as GeoJSON (text) to match the existing
/// `features.geometry_geojson` shape used by the map renderer. The
/// centroid is also denormalized so the map layer doesn't have to
/// re-compute it.
@TableIndex(
  name: 'remote_new_features_cache_assignment_idx',
  columns: {#assignmentId, #updatedAt},
)
class RemoteNewFeaturesCache extends Table {
  TextColumn get id => text()(); // server features.id (uuid)
  TextColumn get assignmentId => text()();
  TextColumn get featureType => text()();
  TextColumn get geometryGeojson => text()();
  RealColumn get centroidLat => real()();
  RealColumn get centroidLng => real()();
  // submitted_by is on the *first* submission for this feature, not the
  // feature row itself. The server RPC includes it so the badge UI can
  // show "added by Alice".
  TextColumn get submittedBy => text().nullable()();
  DateTimeColumn get submittedAt => dateTime()();
  TextColumn get possibleDuplicateOf => text().nullable()();
  DateTimeColumn get dedupReviewedAt => dateTime().nullable()();
  DateTimeColumn get supersededAt => dateTime().nullable()();
  TextColumn get supersededById => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
