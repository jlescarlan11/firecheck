import 'package:drift/drift.dart';

@TableIndex(name: 'fgr_feature_id_idx',  columns: {#featureId})
@TableIndex(name: 'fgr_sync_status_idx', columns: {#syncStatus})
class FeatureGeometryRevisions extends Table {
  TextColumn     get id              => text()();
  TextColumn     get featureId       => text()();
  TextColumn     get prevGeojson     => text()();
  TextColumn     get newGeojson      => text()();
  TextColumn     get editedBy        => text()();
  DateTimeColumn get editedAt        => dateTime()();
  TextColumn     get overrideReason  => text().nullable()();
  TextColumn     get syncStatus      => text().withDefault(const Constant('pending'))();
                                                            // pending|ready_to_upload|uploaded|failed
  DateTimeColumn get createdAt       => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
