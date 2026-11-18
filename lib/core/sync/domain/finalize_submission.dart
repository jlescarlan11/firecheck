import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
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
      final current = await (_db.select(_db.submissions)
            ..where((t) => t.id.equals(submissionId)))
          .getSingle();
      if ({'uploaded', 'queued'}.contains(current.syncStatus)) {
        return FinalizeResult(
          submissionId: submissionId,
          photoCount: await _queuePhotos(submissionId),
          newFeatureQueued: false,
        );
      }
      if (!{'draft', 'in_progress', 'ready_to_upload'}
          .contains(current.syncStatus)) {
        return FinalizeResult(
          submissionId: submissionId,
          photoCount: 0,
          newFeatureQueued: false,
        );
      }
      // 1. Update submission: → queued
      await (_db.update(_db.submissions)
            ..where((t) => t.id.equals(submissionId)))
          .write(
        SubmissionsCompanion(
          syncStatus: const Value('queued'),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // An explicit completed revision owns a fresh immutable operation.
      // Retrying a queued revision returns above and retains its operation.
      final existing =
          await _findJob(SyncEntityType.attributionUpload, submissionId);
      if (existing == null || current.syncStatus == 'ready_to_upload') {
        final operationId = _uuid.v4();
        final frozen = await SubmissionPayloadBuilder(_db).build(submissionId);
        frozen['operation_id'] = operationId;
        await _db.into(_db.syncJobs).insert(
              SyncJobsCompanion.insert(
                id: operationId,
                payloadJson: Value(jsonEncode(frozen)),
                entityType: SyncEntityType.attributionUpload,
                entityId: submissionId,
                createdAt: DateTime.now(),
              ),
            );
      }

      final photoCount = await _queuePhotos(submissionId);

      // 4. New-feature sync_job if applicable (skip-if-exists). Routes
      // through the dedup-aware RPC.
      final submission = await (_db.select(_db.submissions)
            ..where((t) => t.id.equals(submissionId)))
          .getSingle();
      final feature = await (_db.select(_db.features)
            ..where((t) => t.id.equals(submission.featureId)))
          .getSingle();
      var newFeatureQueued = false;
      if (feature.isNew) {
        final existing =
            await _findJob(SyncEntityType.newFeatureUpload, feature.id);
        if (existing == null) {
          await _db.into(_db.syncJobs).insert(
                SyncJobsCompanion.insert(
                  id: _uuid.v4(),
                  entityType: SyncEntityType.newFeatureUpload,
                  entityId: feature.id,
                  createdAt: DateTime.now(),
                ),
              );
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

  Future<int> _queuePhotos(String submissionId) async {
    final photos = await (_db.select(_db.photos)
          ..where((t) => t.submissionId.equals(submissionId)))
        .get();
    var photoCount = 0;
    for (final photo in photos) {
      if (photo.uploadStatus == 'uploaded') continue;
      final existing = await _findJob(SyncEntityType.photo, photo.id);
      if (existing != null) continue;
      await _db.into(_db.syncJobs).insert(
            SyncJobsCompanion.insert(
              id: _uuid.v4(),
              entityType: SyncEntityType.photo,
              entityId: photo.id,
              blocksOnSubmissionId: Value(submissionId),
              createdAt: DateTime.now(),
            ),
          );
      photoCount++;
    }

    return photoCount;
  }

  Future<SyncJob?> _findJob(String entityType, String entityId) {
    return SyncJobsRepository(_db).findByEntity(entityType, entityId);
  }
}
