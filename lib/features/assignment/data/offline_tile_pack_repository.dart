import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';

class OfflineTilePackRepository {
  OfflineTilePackRepository(this._db);
  final AppDatabase _db;

  Stream<OfflineTilePack?> watchForAssignment(String assignmentId) {
    return (_db.select(_db.offlineTilePacks)
          ..where((t) => t.assignmentId.equals(assignmentId))
          ..limit(1))
        .watchSingleOrNull();
  }

  Future<void> upsert({
    required String id,
    required String assignmentId,
    String? mapboxPackId,
    required String regionBoundsGeojson,
    int downloadedBytes = 0,
    int totalBytes = 0,
    String status = 'downloading',
  }) {
    return _db.into(_db.offlineTilePacks).insertOnConflictUpdate(
          OfflineTilePacksCompanion.insert(
            id: id,
            assignmentId: assignmentId,
            mapboxPackId: Value(mapboxPackId),
            regionBoundsGeojson: regionBoundsGeojson,
            downloadedBytes: Value(downloadedBytes),
            totalBytes: Value(totalBytes),
            status: Value(status),
          ),
        );
  }

  Future<void> updateProgress(
    String id,
    int downloadedBytes,
    int totalBytes,
  ) {
    return (_db.update(_db.offlineTilePacks)..where((t) => t.id.equals(id)))
        .write(OfflineTilePacksCompanion(
      downloadedBytes: Value(downloadedBytes),
      totalBytes: Value(totalBytes),
    ));
  }

  Future<void> markReady(String id) {
    return (_db.update(_db.offlineTilePacks)..where((t) => t.id.equals(id)))
        .write(const OfflineTilePacksCompanion(status: Value('ready')));
  }

  Future<void> markError(String id, String message) {
    // The current schema has no error-message column; log only for Phase 1.
    // Phase 4 may add a column if surfaced to UI.
    return (_db.update(_db.offlineTilePacks)..where((t) => t.id.equals(id)))
        .write(const OfflineTilePacksCompanion(status: Value('error')));
  }
}
