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
    String? ownerId,
    String? batchId,
  }) async {
    await _db.into(_db.driveUploadJobs).insert(
          DriveUploadJobsCompanion.insert(
            id: id,
            assignmentId: assignmentId,
            ownerId: Value(ownerId),
            batchId: Value(batchId),
            filePath: filePath,
            fileType: fileType,
            fileName: fileName,
            fileSizeBytes: fileSizeBytes,
            capturedAt: capturedAt,
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<List<DriveUploadJob>> getPendingJobs({
    DateTime? now,
    int? limit,
  }) async {
    if (limit != null && limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }
    final cutoff = now ?? DateTime.now();
    final query = _db.select(_db.driveUploadJobs)
      ..where(
        (t) =>
            t.status.isIn([
              DriveUploadJobStatus.pending,
              DriveUploadJobStatus.failed,
            ]) &
            (t.nextRetryAt.isNull() |
                t.nextRetryAt.isSmallerOrEqualValue(cutoff)),
      )
      ..orderBy([
        (t) => OrderingTerm.asc(t.createdAt),
        (t) => OrderingTerm.asc(t.id),
      ]);
    // Bound rows in SQLite before materializing jobs for the next upload batch.
    if (limit != null) query.limit(limit);
    return query.get();
  }

  /// Only outstanding changes belong in the upload queue. Completed jobs
  /// remain in the database for audit/finalization, outside this bounded view.
  Stream<List<DriveUploadJob>> watchQueue({int limit = 50}) {
    return (_db.select(_db.driveUploadJobs)
          ..where(
            (t) => t.status.isIn(const [
              DriveUploadJobStatus.pending,
              DriveUploadJobStatus.uploading,
              DriveUploadJobStatus.failed,
              DriveUploadJobStatus.dead,
            ]),
          )
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ])
          ..limit(limit))
        .watch();
  }

  /// Counts are computed in SQLite, independently of the loaded row window.
  Stream<UploadQueueTotals> watchQueueTotals() => _db
      .customSelect(
        """
    SELECT COUNT(*) AS active_count,
      COALESCE(SUM(CASE WHEN status != 'uploading' THEN 1 ELSE 0 END), 0) AS pending_count,
      COALESCE(SUM(CASE WHEN status != 'uploading' THEN file_size_bytes ELSE 0 END), 0) AS pending_bytes,
      COALESCE(SUM(CASE WHEN status = 'uploading' THEN 1 ELSE 0 END), 0) AS uploading_count,
      COALESCE(SUM(CASE WHEN status IN ('failed', 'dead') THEN 1 ELSE 0 END), 0) AS failed_count
    FROM drive_upload_jobs
    WHERE status IN ('pending', 'uploading', 'failed', 'dead')
    """,
        readsFrom: {_db.driveUploadJobs},
      )
      .watchSingle()
      .map(
        (row) => UploadQueueTotals(
          activeCount: row.read<int>('active_count'),
          pendingCount: row.read<int>('pending_count'),
          pendingBytes: row.read<int>('pending_bytes'),
          uploadingCount: row.read<int>('uploading_count'),
          failedCount: row.read<int>('failed_count'),
        ),
      );

  Stream<int> watchPendingCount() =>
      watchQueueTotals().map((t) => t.activeCount);

  Future<void> markUploading(String id) async {
    await (_db.update(_db.driveUploadJobs)..where((t) => t.id.equals(id)))
        .write(
      const DriveUploadJobsCompanion(
        status: Value(DriveUploadJobStatus.uploading),
      ),
    );
  }

  Future<void> markCompleted(String id, {required String driveFileId}) async {
    await (_db.update(_db.driveUploadJobs)..where((t) => t.id.equals(id)))
        .write(
      DriveUploadJobsCompanion(
        status: const Value(DriveUploadJobStatus.completed),
        driveFileId: Value(driveFileId),
        resumableUri: const Value(null),
      ),
    );
  }

  Future<void> markFailed(
    String id, {
    required String reason,
    required int retryCount,
    required DateTime nextRetryAt,
  }) async {
    await (_db.update(_db.driveUploadJobs)..where((t) => t.id.equals(id)))
        .write(
      DriveUploadJobsCompanion(
        status: const Value(DriveUploadJobStatus.failed),
        failureReason: Value(reason),
        retryCount: Value(retryCount),
        nextRetryAt: Value(nextRetryAt),
      ),
    );
  }

  Future<void> markDead(String id, {required String reason}) async {
    await (_db.update(_db.driveUploadJobs)..where((t) => t.id.equals(id)))
        .write(
      DriveUploadJobsCompanion(
        status: const Value(DriveUploadJobStatus.dead),
        failureReason: Value(reason),
      ),
    );
  }

  Future<void> setResumableUri(String id, String uri) async {
    await (_db.update(_db.driveUploadJobs)..where((t) => t.id.equals(id)))
        .write(DriveUploadJobsCompanion(resumableUri: Value(uri)));
  }

  Future<void> resetForRetry(String id) async {
    await (_db.update(_db.driveUploadJobs)..where((t) => t.id.equals(id)))
        .write(
      const DriveUploadJobsCompanion(
        status: Value(DriveUploadJobStatus.pending),
        retryCount: Value(0),
        failureReason: Value(null),
        nextRetryAt: Value(null),
      ),
    );
  }

  Future<void> resetStuckUploadingToPending() async {
    await (_db.update(_db.driveUploadJobs)
          ..where((t) => t.status.equals(DriveUploadJobStatus.uploading)))
        .write(
      const DriveUploadJobsCompanion(
        status: Value(DriveUploadJobStatus.pending),
        nextRetryAt: Value(null),
      ),
    );
  }

  Future<void> resetFailedToPending() async {
    await (_db.update(_db.driveUploadJobs)
          ..where(
            (t) => t.status.isIn([
              DriveUploadJobStatus.failed,
              DriveUploadJobStatus.dead,
            ]),
          ))
        .write(
      const DriveUploadJobsCompanion(
        status: Value(DriveUploadJobStatus.pending),
        retryCount: Value(0),
        failureReason: Value(null),
        nextRetryAt: Value(null),
      ),
    );
  }

  Future<bool> jobExistsForFilePath(String filePath) async {
    final row = await (_db.select(_db.driveUploadJobs)
          ..where((t) => t.filePath.equals(filePath))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  /// True when there's a shapefile upload job actively in flight for
  /// [assignmentId] — pending or uploading.
  ///
  /// Completed and dead jobs do not block re-enqueue: after a successful
  /// upload the enumerator may re-export and re-upload; server-side
  /// supersede handles attribution conflicts.
  ///
  /// Failed jobs are also NOT counted as in-flight: every fresh enqueue
  /// produces new files in a timestamped subdir, so blocking on stale
  /// failed jobs would force the user to wait for retries that will keep
  /// hitting "file missing" against paths that no longer exist. Worker
  /// retries on the legacy failed jobs continue independently; they're
  /// harmless once they exhaust attempts.
  Future<bool> shapefileJobExistsForAssignment(String assignmentId,
      {String? ownerId}) async {
    final row = await (_db.select(_db.driveUploadJobs)
          ..where(
            (t) =>
                t.assignmentId.equals(assignmentId) &
                (ownerId == null
                    ? const Constant(true)
                    : t.ownerId.equals(ownerId)) &
                t.fileType.equals(DriveFileType.shapefile) &
                t.status.isIn(const [
                  DriveUploadJobStatus.pending,
                  DriveUploadJobStatus.uploading,
                ]),
          )
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

class UploadQueueTotals {
  const UploadQueueTotals({
    required this.activeCount,
    required this.pendingCount,
    required this.pendingBytes,
    required this.uploadingCount,
    required this.failedCount,
  });
  final int activeCount;
  final int pendingCount;
  final int pendingBytes;
  final int uploadingCount;
  final int failedCount;
}
