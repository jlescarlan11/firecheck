import 'package:drift/drift.dart';

/// Local mirror of remote `public.submissions` rows for assignments the
/// current user is a member of. Populated by cold-open pull, on-reconnect
/// delta pull, and realtime events (phase 3). Read-only from the UI's
/// perspective — never blocks local edits.
///
/// `attributeValuesJson` is the denormalized child-table data shaped as
/// jsonb: `{ "building": {...}, "road": null, "household": null }`.
/// The server-side `fetch_remote_attributions` RPC composes it from the
/// three typed child tables in a single round-trip.
@TableIndex(
  name: 'remote_attributions_cache_feature_idx',
  columns: {#assignmentId, #featureId},
)
@TableIndex(
  name: 'remote_attributions_cache_updated_at_idx',
  columns: {#assignmentId, #updatedAt},
)
class RemoteAttributionsCache extends Table {
  TextColumn get id => text()(); // server submissions.id (uuid)
  TextColumn get assignmentId => text()();
  TextColumn get featureId => text()();
  TextColumn get featureType => text()(); // building|road
  TextColumn get attributeValuesJson => text()();
  // Nullable to match server `submitted_by uuid references enumerators(id)
  // on delete set null`.
  TextColumn get submittedBy => text().nullable()();
  DateTimeColumn get submittedAt => dateTime()();
  DateTimeColumn get supersededAt => dateTime().nullable()();
  TextColumn get supersededById => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  // Tracks when the local cache row was written; useful for diagnostics
  // and for "stale cache" detection (>24h ⇒ force full pull, per spec).
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
