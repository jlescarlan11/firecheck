import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:uuid/uuid.dart';

class FeatureGeometryRevisionsRepository {
  FeatureGeometryRevisionsRepository(this._db, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Uuid _uuid;

  /// Atomically:
  ///  1. updates `features.geometry_geojson` to [newGeojson]
  ///  2. inserts a `feature_geometry_revisions` row with status `ready_to_upload`
  ///  3. inserts a `sync_jobs` row (`entity_type='feature_geometry_update'`, status `pending`)
  Future<void> saveReshape({
    required String revisionId,
    required String featureId,
    required String prevGeojson,
    required String newGeojson,
    required String editedBy,
    required DateTime editedAt,
    required String? overrideReason,
  }) async {
    await _db.transaction(() async {
      await (_db.update(_db.features)..where((t) => t.id.equals(featureId)))
          .write(FeaturesCompanion(geometryGeojson: Value(newGeojson)));

      await _db.into(_db.featureGeometryRevisions).insert(
            FeatureGeometryRevisionsCompanion.insert(
              id: revisionId,
              featureId: featureId,
              prevGeojson: prevGeojson,
              newGeojson: newGeojson,
              editedBy: editedBy,
              editedAt: editedAt,
              overrideReason: Value(overrideReason),
              syncStatus: const Value('ready_to_upload'),
              createdAt: DateTime.now(),
            ),
          );

      await _db.into(_db.syncJobs).insert(
            SyncJobsCompanion.insert(
              id: _uuid.v4(),
              entityType: 'feature_geometry_update',
              entityId: revisionId,
              createdAt: DateTime.now(),
            ),
          );
    });
  }

  Future<FeatureGeometryRevision?> getById(String id) {
    return (_db.select(_db.featureGeometryRevisions)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> markSynced(String id) async {
    await (_db.update(_db.featureGeometryRevisions)
          ..where((t) => t.id.equals(id)))
        .write(const FeatureGeometryRevisionsCompanion(
            syncStatus: Value('uploaded')));
  }

  Future<void> markFailed(String id) async {
    await (_db.update(_db.featureGeometryRevisions)
          ..where((t) => t.id.equals(id)))
        .write(const FeatureGeometryRevisionsCompanion(
            syncStatus: Value('failed')));
  }
}
