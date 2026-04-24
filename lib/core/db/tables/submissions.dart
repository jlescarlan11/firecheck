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
  TextColumn get syncStatus =>
      text().withDefault(const Constant('draft'))(); // draft|queued|uploading|uploaded|failed|dead
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
