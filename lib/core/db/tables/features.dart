import 'package:drift/drift.dart';

@TableIndex(name: 'features_assignment_id_idx', columns: {#assignmentId})
class Features extends Table {
  TextColumn get id => text()();
  TextColumn get assignmentId => text()();
  TextColumn get featureType => text()(); // building|road
  TextColumn get geometryGeojson => text()();
  BoolColumn get isNew => boolean().withDefault(const Constant(false))();
  TextColumn get status =>
      text().withDefault(const Constant('unfilled'))(); // unfilled|in_progress|complete
  // When the server's dedup-aware upload returns `dedup_pending`, the
  // UUID of the existing canonical row it might duplicate is stored here.
  // Non-null = "needs user review"; cleared once the user resolves.
  // Mirrors the server's `features.possible_duplicate_of` column.
  TextColumn get pendingDedupOf => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
