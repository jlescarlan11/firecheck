import 'package:drift/drift.dart';

@TableIndex(name: 'submissions_feature_id_idx', columns: {#featureId})
class Submissions extends Table {
  TextColumn get id => text()();
  TextColumn get featureId => text()();
  // Nullable to match server: `submitted_by uuid references enumerators(id)
  // on delete set null`. Preserves audit trail if the enumerator account
  // is later removed.
  TextColumn get submittedBy => text().nullable()();
  BoolColumn get doesNotExist => boolean().withDefault(const Constant(false))();
  TextColumn get remarks => text().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('draft'))();
  TextColumn get overrideReason => text().nullable()();
  // When the server returns status=conflict, we store the conflicting
  // canonical's UUID here so the review UI can render side-by-side
  // comparison without re-querying. Null for non-conflict submissions;
  // cleared on resolve.
  TextColumn get pendingTheirsId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
