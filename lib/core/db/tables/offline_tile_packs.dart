import 'package:drift/drift.dart';

class OfflineTilePacks extends Table {
  TextColumn get id => text()();
  TextColumn get assignmentId => text()();
  TextColumn get mapboxPackId => text().nullable()();
  TextColumn get regionBoundsGeojson => text()();
  IntColumn get downloadedBytes => integer().withDefault(const Constant(0))();
  IntColumn get totalBytes => integer().withDefault(const Constant(0))();
  TextColumn get status =>
      text().withDefault(const Constant('downloading'))(); // downloading|ready|error

  @override
  Set<Column> get primaryKey => {id};
}
