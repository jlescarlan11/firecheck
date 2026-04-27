import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/domain/sync_entity_type.dart';
import 'package:uuid/uuid.dart';

class FinalizeResult {
  const FinalizeResult({
    required this.submissionId,
    required this.photoCount,
    required this.newFeatureQueued,
  });
  final String submissionId;
  final int photoCount;
  final bool newFeatureQueued;
}

class FinalizeSubmissionUseCase {
  FinalizeSubmissionUseCase(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  Future<FinalizeResult> execute(String submissionId) async {
    return _db.transaction(() async {
      // 1. Update submission: → queued
      await (_db.update(_db.submissions)
            ..where((t) => t.id.equals(submissionId)))
          .write(SubmissionsCompanion(
        syncStatus: const Value('queued'),
        updatedAt: Value(DateTime.now()),
      ),);

      // 2. Submission sync_job (skip-if-exists)
      final existingSub =
          await _findJob(SyncEntityType.submission, submissionId);
      if (existingSub == null) {
        await _db.into(_db.syncJobs).insert(SyncJobsCompanion.insert(
              id: _uuid.v4(),
              entityType: SyncEntityType.submission,
              entityId: submissionId,
              createdAt: DateTime.now(),
            ),);
      }

      // 3. Photo sync_jobs (skip-if-exists)
      final photos = await (_db.select(_db.photos)
            ..where((t) => t.submissionId.equals(submissionId)))
          .get();
      var photoCount = 0;
      for (final photo in photos) {
        final existing = await _findJob(SyncEntityType.photo, photo.id);
        if (existing != null) continue;
        await _db.into(_db.syncJobs).insert(SyncJobsCompanion.insert(
              id: _uuid.v4(),
              entityType: SyncEntityType.photo,
              entityId: photo.id,
              blocksOnSubmissionId: Value(submissionId),
              createdAt: DateTime.now(),
            ),);
        photoCount++;
      }

      // 4. New-feature sync_job if applicable (skip-if-exists)
      final submission = await (_db.select(_db.submissions)
            ..where((t) => t.id.equals(submissionId)))
          .getSingle();
      final feature = await (_db.select(_db.features)
            ..where((t) => t.id.equals(submission.featureId)))
          .getSingle();
      var newFeatureQueued = false;
      if (feature.isNew) {
        final existing =
            await _findJob(SyncEntityType.newFeature, feature.id);
        if (existing == null) {
          await _db.into(_db.syncJobs).insert(SyncJobsCompanion.insert(
                id: _uuid.v4(),
                entityType: SyncEntityType.newFeature,
                entityId: feature.id,
                createdAt: DateTime.now(),
              ),);
          newFeatureQueued = true;
        }
      }

      return FinalizeResult(
        submissionId: submissionId,
        photoCount: photoCount,
        newFeatureQueued: newFeatureQueued,
      );
    });
  }

  Future<SyncJob?> _findJob(String entityType, String entityId) {
    return (_db.select(_db.syncJobs)
          ..where(
            (t) =>
                t.entityType.equals(entityType) & t.entityId.equals(entityId),
          ))
        .getSingleOrNull();
  }
}
