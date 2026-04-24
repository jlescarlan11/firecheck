import 'package:drift/drift.dart';

class Submissions extends Table {
  TextColumn get id => text()();
  TextColumn get featureId => text()();
  TextColumn get submittedBy => text()();
  BoolColumn get doesNotExist => boolean().withDefault(const Constant(false))();
  TextColumn get remarks => text().nullable()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('draft'))(); // draft|queued|uploading|uploaded|failed|dead
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
