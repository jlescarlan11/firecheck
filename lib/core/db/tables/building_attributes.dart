import 'package:drift/drift.dart';

class BuildingAttributes extends Table {
  TextColumn get submissionId => text()();
  TextColumn get cbmsId => text().nullable()();
  TextColumn get buildingName => text().nullable()();
  TextColumn get ra9514Type => text().nullable()();
  IntColumn get storeys => integer().nullable()();
  TextColumn get material => text().nullable()();
  BoolColumn get costIsExact => boolean().withDefault(const Constant(false))();
  RealColumn get costAmount => real().nullable()();
  TextColumn get costEstimateRange => text().nullable()();
  TextColumn get fireFightingFacilitiesJson =>
      text().withDefault(const Constant('[]'))();
  TextColumn get fireLoadJson => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {submissionId};
}
