import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';

class DriveUploadRepository {
  DriveUploadRepository(this._db);
  final AppDatabase _db;

  Future<void> insertJob({
    required String id,
    required String assignmentId,
    required String filePath,
    required String fileType,
    required String fileName,
    required int fileSizeBytes,
    required DateTime capturedAt,
  }) async {
    await _db.into(_db.driveUploadJobs).insert(
          DriveUploadJobsCompanion.insert(
            id: id,
            assignmentId: assignmentId,
            filePath: filePath,
            fileType: fileType,
            fileName: fileName,
            fileSizeBytes: fileSizeBytes,
            capturedAt: capturedAt,
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<List<DriveUploadJob>> getPendingJobs({DateTime? now}) async {
    final cutoff = now ?? DateTime.now();
    return (_db.select(_db.driveUploadJobs)
          ..where(
            (t) =>
                t.status.isIn([
                  DriveUploadJobStatus.pending,
                  DriveUploadJobStatus.failed,
                ]) &
                (t.nextRetryAt.isNull() |
                    t.nextRetryAt.isSmallerOrEqualValue(cutoff)),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Stream<List<DriveUploadJob>> watchQueue() {
    return (_db.select(_db.driveUploadJobs)
          ..where((t) => t.status.isIn([
                DriveUploadJobStatus.pending,
                DriveUploadJobStatus.uploading,
                DriveUploadJobStatus.failed,
                DriveUploadJobStatus.dead,
                DriveUploadJobStatus.completed,
              ]))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  Stream<int> watchPendingCount() {
    return watchQueue().map((jobs) => jobs.length);
  }

  Future<void> markUploading(String id) async {
    await (_db.update(_db.driveUploadJobs)..where((t) => t.id.equals(id)))
        .write(const DriveUploadJobsCompanion(
      status: Value(DriveUploadJobStatus.uploading),
    ));
  }

  Future<void> markCompleted(String id, {required String driveFileId}) async {
    await (_db.update(_db.driveUploadJobs)..where((t) => t.id.equals(id)))
        .write(DriveUploadJobsCompanion(
      status: const Value(DriveUploadJobStatus.completed),
      driveFileId: Value(driveFileId),
      resumableUri: const Value(null),
    ));
  }

  Future<void> markFailed(
    String id, {
    required String reason,
    required int retryCount,
    required DateTime nextRetryAt,
  }) async {
    await (_db.update(_db.driveUploadJobs)..where((t) => t.id.equals(id)))
        .write(DriveUploadJobsCompanion(
      status: const Value(DriveUploadJobStatus.failed),
      failureReason: Value(reason),
      retryCount: Value(retryCount),
      nextRetryAt: Value(nextRetryAt),
    ));
  }

  Future<void> markDead(String id, {required String reason}) async {
    await (_db.update(_db.driveUploadJobs)..where((t) => t.id.equals(id)))
        .write(DriveUploadJobsCompanion(
      status: const Value(DriveUploadJobStatus.dead),
      failureReason: Value(reason),
    ));
  }

  Future<void> setResumableUri(String id, String uri) async {
    await (_db.update(_db.driveUploadJobs)..where((t) => t.id.equals(id)))
        .write(DriveUploadJobsCompanion(resumableUri: Value(uri)));
  }

  Future<void> resetForRetry(String id) async {
    await (_db.update(_db.driveUploadJobs)..where((t) => t.id.equals(id)))
        .write(const DriveUploadJobsCompanion(
      status: Value(DriveUploadJobStatus.pending),
      retryCount: Value(0),
      failureReason: Value(null),
      nextRetryAt: Value(null),
    ));
  }

  Future<void> resetStuckUploadingToPending() async {
    await (_db.update(_db.driveUploadJobs)
          ..where((t) => t.status.equals(DriveUploadJobStatus.uploading)))
        .write(const DriveUploadJobsCompanion(
      status: Value(DriveUploadJobStatus.pending),
      nextRetryAt: Value(null),
    ));
  }

  Future<void> resetFailedToPending() async {
    await (_db.update(_db.driveUploadJobs)
          ..where((t) => t.status.equals(DriveUploadJobStatus.failed)))
        .write(const DriveUploadJobsCompanion(
      status: Value(DriveUploadJobStatus.pending),
      nextRetryAt: Value(null),
    ));
  }

  Future<bool> jobExistsForFilePath(String filePath) async {
    final row = await (_db.select(_db.driveUploadJobs)
          ..where((t) => t.filePath.equals(filePath))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  Future<bool> shapefileJobExistsForAssignment(String assignmentId) async {
    final row = await (_db.select(_db.driveUploadJobs)
          ..where((t) =>
              t.assignmentId.equals(assignmentId) &
              t.fileType.equals(DriveFileType.shapefile))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  Future<List<DriveUploadJob>> getJobsForAssignment(String assignmentId) {
    return (_db.select(_db.driveUploadJobs)
          ..where((t) => t.assignmentId.equals(assignmentId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }
}
