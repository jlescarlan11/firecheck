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
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
