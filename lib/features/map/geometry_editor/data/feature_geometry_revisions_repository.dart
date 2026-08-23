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

  /// Persists both halves and one replayable outbox operation atomically.
  Future<String> saveSplit({
    required String revisionId,
    required Feature source,
    required String firstGeojson,
    required String secondGeojson,
    required String editedBy,
    required DateTime editedAt,
  }) async {
    final secondId = _uuid.v4();
    await _db.transaction(() async {
      await (_db.update(_db.features)..where((t) => t.id.equals(source.id)))
          .write(FeaturesCompanion(geometryGeojson: Value(firstGeojson)));
      await _db.into(_db.features).insert(
            FeaturesCompanion.insert(
              id: secondId,
              assignmentId: source.assignmentId,
              featureType: source.featureType,
              geometryGeojson: secondGeojson,
              isNew: const Value(true),
              status: Value(source.status),
              splitFromId: Value(source.id),
              createdAt: editedAt,
            ),
          );
      await _insertOperation(
        revisionId: revisionId,
        featureId: source.id,
        prevGeojson: source.geometryGeojson,
        newGeojson: firstGeojson,
        operation: 'split',
        relatedFeatureId: secondId,
        relatedGeojson: secondGeojson,
        editedBy: editedBy,
        editedAt: editedAt,
      );
    });
    return secondId;
  }

  /// Replaces [primary] and tombstones [secondary] in one local transaction.
  Future<void> saveMerge({
    required String revisionId,
    required Feature primary,
    required Feature secondary,
    required String mergedGeojson,
    required String editedBy,
    required DateTime editedAt,
  }) async {
    if (primary.assignmentId != secondary.assignmentId ||
        primary.featureType != secondary.featureType) {
      throw ArgumentError(
          'Only same-type features in one assignment can merge');
    }
    await _db.transaction(() async {
      await (_db.update(_db.features)..where((t) => t.id.equals(primary.id)))
          .write(FeaturesCompanion(geometryGeojson: Value(mergedGeojson)));
      await (_db.update(_db.features)..where((t) => t.id.equals(secondary.id)))
          .write(FeaturesCompanion(mergedIntoId: Value(primary.id)));
      await _insertOperation(
        revisionId: revisionId,
        featureId: primary.id,
        prevGeojson: primary.geometryGeojson,
        newGeojson: mergedGeojson,
        operation: 'merge',
        relatedFeatureId: secondary.id,
        relatedGeojson: secondary.geometryGeojson,
        editedBy: editedBy,
        editedAt: editedAt,
      );
    });
  }

  Future<void> _insertOperation({
    required String revisionId,
    required String featureId,
    required String prevGeojson,
    required String newGeojson,
    required String operation,
    required String relatedFeatureId,
    required String relatedGeojson,
    required String editedBy,
    required DateTime editedAt,
  }) async {
    await _db.into(_db.featureGeometryRevisions).insert(
          FeatureGeometryRevisionsCompanion.insert(
            id: revisionId,
            featureId: featureId,
            prevGeojson: prevGeojson,
            newGeojson: newGeojson,
            editedBy: editedBy,
            editedAt: editedAt,
            operation: Value(operation),
            relatedFeatureId: Value(relatedFeatureId),
            relatedGeojson: Value(relatedGeojson),
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

  /// Explicitly accepts the canonical server geometry after a conflict.
  /// Nothing changes until this user-selected resolution is invoked.
  Future<void> resolveKeepingServer({
    required String revisionId,
    required String serverGeojson,
  }) async {
    await _db.transaction(() async {
      final revision = await getById(revisionId);
      if (revision == null || revision.syncStatus != 'failed') {
        throw StateError('Only failed geometry revisions can be resolved');
      }
      if (revision.operation == 'split' && revision.relatedFeatureId != null) {
        await (_db.delete(_db.features)
              ..where(
                (feature) => feature.id.equals(revision.relatedFeatureId!),
              ))
            .go();
      } else if (revision.operation == 'merge' &&
          revision.relatedFeatureId != null) {
        await (_db.update(_db.features)
              ..where(
                (feature) => feature.id.equals(revision.relatedFeatureId!),
              ))
            .write(
          FeaturesCompanion(
            mergedIntoId: const Value(null),
            geometryGeojson: Value(revision.relatedGeojson!),
          ),
        );
      }
      await (_db.update(_db.features)
            ..where((feature) => feature.id.equals(revision.featureId)))
          .write(FeaturesCompanion(geometryGeojson: Value(serverGeojson)));
      await (_db.update(_db.featureGeometryRevisions)
            ..where((row) => row.id.equals(revisionId)))
          .write(
        const FeatureGeometryRevisionsCompanion(
          syncStatus: Value('discarded'),
        ),
      );
    });
  }

  /// Rebases the user's edit on the confirmed server geometry and requeues it.
  Future<void> resolveRetryingLocal({
    required String revisionId,
    required String serverGeojson,
  }) async {
    await _db.transaction(() async {
      final revision = await getById(revisionId);
      if (revision == null || revision.syncStatus != 'failed') {
        throw StateError('Only failed geometry revisions can be resolved');
      }
      await (_db.update(_db.featureGeometryRevisions)
            ..where((row) => row.id.equals(revisionId)))
          .write(
        FeatureGeometryRevisionsCompanion(
          prevGeojson: Value(serverGeojson),
          syncStatus: const Value('ready_to_upload'),
        ),
      );
      await (_db.update(_db.syncJobs)
            ..where(
              (job) =>
                  job.entityType.equals('feature_geometry_update') &
                  job.entityId.equals(revisionId),
            ))
          .write(
        const SyncJobsCompanion(
          status: Value('pending'),
          attempts: Value(0),
          lastError: Value(null),
          nextRetryAt: Value(null),
        ),
      );
    });
  }
}
