import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/photos/photo_storage_service.dart';
import 'package:uuid/uuid.dart';

class PhotoRepository {
  PhotoRepository({required this.db, required this.storage});
  final AppDatabase db;
  final PhotoStorageService storage;

  Stream<List<Photo>> watchForSubmission(String submissionId) {
    return (db.select(db.photos)
          ..where((t) => t.submissionId.equals(submissionId))
          ..orderBy([(t) => OrderingTerm.asc(t.capturedAt)]))
        .watch();
  }

  Future<int> countForSubmission(String submissionId) async {
    final rows = await (db.select(db.photos)
          ..where((t) => t.submissionId.equals(submissionId)))
        .get();
    return rows.length;
  }

  /// Inserts a Drift row referencing an already-on-disk file. Returns the
  /// new photo id.
  Future<String> insert({
    required String submissionId,
    required String localPath,
    required DateTime capturedAt,
    double? gpsLat,
    double? gpsLng,
  }) async {
    final id = const Uuid().v4();
    await db.into(db.photos).insert(
          PhotosCompanion.insert(
            id: id,
            submissionId: submissionId,
            localPath: localPath,
            capturedAt: capturedAt,
            gpsLat: Value(gpsLat),
            gpsLng: Value(gpsLng),
            createdAt: DateTime.now(),
          ),
        );
    return id;
  }

  /// Removes the Drift row AND deletes the file from disk.
  Future<void> delete(String photoId) async {
    final row = await (db.select(db.photos)..where((t) => t.id.equals(photoId)))
        .getSingleOrNull();
    if (row == null) return;
    await storage.deleteFile(row.localPath);
    await (db.delete(db.photos)..where((t) => t.id.equals(photoId))).go();
  }
}
