import 'package:drift/drift.dart';

class Assignments extends Table {
  TextColumn get id => text()();
  TextColumn get enumeratorId => text()();
  TextColumn get campaignId => text()();
  TextColumn get boundaryPolygonGeojson => text()();
  DateTimeColumn get downloadedAt => dateTime().nullable()();
  DateTimeColumn get submittedAt => dateTime().nullable()();
  TextColumn get status =>
      text().withDefault(const Constant('assigned'))(); // assigned|in_progress|submitted
  BoolColumn get closedRemotely => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
