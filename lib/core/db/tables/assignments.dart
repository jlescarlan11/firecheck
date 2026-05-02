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
  TextColumn get driveModifiedTime => text().nullable()();
  TextColumn get driveFolderId => text().nullable()();
  // US-30: Drive upload confirmation
  TextColumn get driveFolderPath => text().nullable()();
  TextColumn get driveFolderUrl => text().nullable()();
  DateTimeColumn get driveUploadConfirmedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
