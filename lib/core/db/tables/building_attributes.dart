import 'package:drift/drift.dart';

@TableIndex(name: 'building_attrs_ra9514_type_idx', columns: {#ra9514Type})
class BuildingAttributes extends Table {
  TextColumn get submissionId => text()();
  TextColumn get cbmsId => text().nullable()();
  TextColumn get buildingName => text().nullable()();
  // Pinned to match server column name `ra_9514_type`. Drift's default
  // snake_case conversion would produce `ra9514_type` (no underscore
  // between `ra` and `9514`), which would mismatch the server schema.
  TextColumn get ra9514Type =>
      text().nullable().named('ra_9514_type')();
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
