import 'package:drift/drift.dart';

class RoadAttributes extends Table {
  TextColumn get submissionId => text()();
  BoolColumn get isBridge => boolean().withDefault(const Constant(false))();
  TextColumn get roadName => text().nullable()();
  RealColumn get widthMeters => real().nullable()();
  TextColumn get roadFeaturesJson => text().withDefault(const Constant('[]'))();
  TextColumn get othersDescription => text().nullable()();

  @override
  Set<Column> get primaryKey => {submissionId};
}
