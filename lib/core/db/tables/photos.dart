import 'package:drift/drift.dart';

class Photos extends Table {
  TextColumn get id => text()();
  TextColumn get submissionId => text()();
  TextColumn get localPath => text()();
  TextColumn get storagePath => text().nullable()();
  DateTimeColumn get capturedAt => dateTime()();
  RealColumn get gpsLat => real().nullable()();
  RealColumn get gpsLng => real().nullable()();
  TextColumn get uploadStatus =>
      text().withDefault(const Constant('pending'))(); // pending|uploaded|failed
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
