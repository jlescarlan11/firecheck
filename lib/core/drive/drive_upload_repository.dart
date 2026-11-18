import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';

class DriveUploadRepository {
  DriveUploadRepository(this._db);
  final AppDatabase _db;

  static const _retryValues = DriveUploadJobsCompanion(
    status: Value(DriveUploadJobStatus.pending),
    retryCount: Value(0),
    failureReason: Value(null),
    nextRetryAt: Value(null),
  );
  static const _unfinishedExportStatuses = [
    DriveUploadJobStatus.pending,
    DriveUploadJobStatus.uploading,
    DriveUploadJobStatus.failed,
  ];

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

  /// Once a newer revision starts writing stable Drive component names, every
  /// component of the older revision must stay outside retry and claim paths.
  /// First insertion orders batches even when timestamps tie or a later row is
  /// appended to an older batch. Null batch IDs retain their legacy grouping.
  static String _notSupersededExport(String candidate) => """
    $candidate.file_type != 'shapefile' OR NOT EXISTS (
      SELECT 1 FROM drive_upload_jobs newer
      WHERE newer.assignment_id=$candidate.assignment_id
        AND newer.owner_id IS $candidate.owner_id
        AND newer.file_type='shapefile'
        AND newer.batch_id IS NOT $candidate.batch_id
        AND newer.status IN ('uploading','completed')
        AND (
          SELECT MIN(batch.rowid) FROM drive_upload_jobs batch
          WHERE batch.assignment_id=newer.assignment_id
            AND batch.owner_id IS newer.owner_id
            AND batch.file_type='shapefile' AND batch.batch_id IS newer.batch_id
        ) > (
          SELECT MIN(batch.rowid) FROM drive_upload_jobs batch
          WHERE batch.assignment_id=$candidate.assignment_id
            AND batch.owner_id IS $candidate.owner_id
            AND batch.file_type='shapefile' AND batch.batch_id IS $candidate.batch_id
        )
    )
    """;

  static String _hasNoEarlierExport(String candidate) => """
    NOT EXISTS (
      SELECT 1 FROM drive_upload_jobs earlier
      WHERE earlier.assignment_id=$candidate.assignment_id
        AND earlier.owner_id IS $candidate.owner_id
        AND earlier.rowid < $candidate.rowid
        AND earlier.batch_id IS NOT $candidate.batch_id
        AND earlier.file_type='shapefile' AND $candidate.file_type='shapefile'
        AND earlier.status IN ('pending','uploading','failed')
        AND (${_notSupersededExport('earlier')})
    )
    """;

  Future<List<DriveUploadJob>> getPendingJobs({
    DateTime? now,
    int? limit,
    String? ownerId,
  }) async {
    if (limit != null && limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }
    final cutoff = now ?? DateTime.now();
    final rows = await _db.customSelect(
      """
      SELECT j.* FROM drive_upload_jobs j
      WHERE j.status IN ('pending','failed') AND (? IS NULL OR j.owner_id=?)
        AND (j.next_retry_at IS NULL OR j.next_retry_at <= ?)
        AND (${_notSupersededExport('j')})
        AND (${_hasNoEarlierExport('j')})
      ORDER BY j.rowid LIMIT ?
      """,
      variables: [
        Variable<String>(ownerId),
        Variable<String>(ownerId),
        Variable.withDateTime(cutoff),
        Variable.withInt(limit ?? -1),
      ],
      readsFrom: {_db.driveUploadJobs},
    ).get();
    return rows.map((row) => _db.driveUploadJobs.map(row.data)).toList();
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

  /// Selection is only a hint. This single SQLite transition rechecks the
  /// original account, eligibility, FIFO and supersession before remote I/O.
  Future<bool> claimForUpload(
    String id, {
    required String ownerId,
    required String processIdentity,
    DateTime? now,
  }) async {
    if (processIdentity.isEmpty) return false;
    final cutoff = now ?? DateTime.now();
    final changed = await (_db.update(_db.driveUploadJobs)
          ..where(
            (t) =>
                t.id.equals(id) &
                t.ownerId.equals(ownerId) &
                t.status.isIn(
                  [DriveUploadJobStatus.pending, DriveUploadJobStatus.failed],
                ) &
                (t.nextRetryAt.isNull() |
                    t.nextRetryAt.isSmallerOrEqualValue(cutoff)) &
                CustomExpression<bool>(
                  _notSupersededExport('drive_upload_jobs'),
                ) &
                CustomExpression<bool>(
                  _hasNoEarlierExport('drive_upload_jobs'),
                ),
          ))
        .write(
      DriveUploadJobsCompanion(
        status: const Value(DriveUploadJobStatus.uploading),
        claimProcessIdentity: Value(processIdentity),
      ),
    );
    return changed == 1;
  }

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
        claimProcessIdentity: const Value(null),
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
        claimProcessIdentity: const Value(null),
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
        claimProcessIdentity: const Value(null),
        failureReason: Value(reason),
      ),
    );
  }

  Future<void> setResumableUri(String id, String uri) async {
    await (_db.update(_db.driveUploadJobs)..where((t) => t.id.equals(id)))
        .write(DriveUploadJobsCompanion(resumableUri: Value(uri)));
  }

  Future<void> resetForRetry(String id, {String? ownerId}) async {
    await (_db.update(_db.driveUploadJobs)
          ..where(
            (t) =>
                t.id.equals(id) &
                t.status.isNotValue(DriveUploadJobStatus.uploading) &
                CustomExpression<bool>(
                  _notSupersededExport('drive_upload_jobs'),
                ) &
                (ownerId == null
                    ? const Constant(true)
                    : t.ownerId.equals(ownerId)),
          ))
        .write(
      _retryValues,
    );
  }

  Future<void> resetStuckUploadingToPending({
    String? ownerId,
    String? processIdentity,
  }) async {
    await (_db.update(_db.driveUploadJobs)
          ..where(
            (t) =>
                t.status.equals(DriveUploadJobStatus.uploading) &
                (t.claimProcessIdentity.isNull() |
                    (processIdentity == null || processIdentity.isEmpty
                        ? const Constant(false)
                        : t.claimProcessIdentity.isNotValue(processIdentity))) &
                (ownerId == null
                    ? const Constant(true)
                    : t.ownerId.equals(ownerId)),
          ))
        .write(
      const DriveUploadJobsCompanion(
        status: Value(DriveUploadJobStatus.pending),
        claimProcessIdentity: Value(null),
        nextRetryAt: Value(null),
      ),
    );
  }

  Future<void> releaseForAccountChange(String jobId, String ownerId) async {
    await (_db.update(_db.driveUploadJobs)
          ..where(
            (t) =>
                t.id.equals(jobId) &
                t.ownerId.equals(ownerId) &
                t.status.equals(DriveUploadJobStatus.uploading),
          ))
        .write(
      const DriveUploadJobsCompanion(
        status: Value(DriveUploadJobStatus.pending),
        claimProcessIdentity: Value(null),
        nextRetryAt: Value(null),
      ),
    );
  }

  Future<void> resetFailedToPending({String? ownerId}) async {
    await (_db.update(_db.driveUploadJobs)
          ..where(
            (t) =>
                t.status.isIn([
                  DriveUploadJobStatus.failed,
                  DriveUploadJobStatus.dead,
                ]) &
                CustomExpression<bool>(
                  _notSupersededExport('drive_upload_jobs'),
                ) &
                (ownerId == null
                    ? const Constant(true)
                    : t.ownerId.equals(ownerId)),
          ))
        .write(
      _retryValues,
    );
  }

  Future<bool> jobExistsForFilePath(String filePath) async {
    final row = await (_db.select(_db.driveUploadJobs)
          ..where((t) => t.filePath.equals(filePath))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  /// Pending, uploading, and failed exports retain their immutable batch.
  /// Enqueue compares current component content before deciding whether a
  /// later intentional revision needs a different batch. Completed/dead jobs
  /// remain as evidence but do not alone prevent a fresh export.
  Future<bool> shapefileJobExistsForAssignment(
    String assignmentId, {
    String? ownerId,
  }) async {
    final row = await (_db.select(_db.driveUploadJobs)
          ..where(
            (t) =>
                t.assignmentId.equals(assignmentId) &
                (ownerId == null
                    ? const Constant(true)
                    : t.ownerId.equals(ownerId)) &
                t.fileType.equals(DriveFileType.shapefile) &
                t.status.isIn(_unfinishedExportStatuses),
          )
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  Future<List<DriveUploadJob>> latestUnfinishedExportBatch(
    String assignmentId, {
    String? ownerId,
  }) async {
    final latest = await _db.customSelect(
      """
      SELECT * FROM drive_upload_jobs WHERE assignment_id=? AND file_type='shapefile'
        AND (? IS NULL OR owner_id=?) AND status IN ('pending','uploading','failed')
      ORDER BY rowid DESC LIMIT 1
      """,
      variables: [
        Variable.withString(assignmentId),
        Variable<String>(ownerId),
        Variable<String>(ownerId),
      ],
      readsFrom: {_db.driveUploadJobs},
    ).getSingleOrNull();
    if (latest == null) return [];
    final job = _db.driveUploadJobs.map(latest.data);
    return (await getJobsForAssignment(assignmentId))
        .where(
          (candidate) =>
              candidate.fileType == DriveFileType.shapefile &&
              candidate.ownerId == job.ownerId &&
              candidate.batchId == job.batchId,
        )
        .toList();
  }

  Future<List<DriveUploadJob>> getJobsForAssignment(String assignmentId) {
    return _db
        .customSelect(
          'SELECT * FROM drive_upload_jobs WHERE assignment_id=? ORDER BY rowid',
          variables: [Variable.withString(assignmentId)],
          readsFrom: {_db.driveUploadJobs},
        )
        .get()
        .then(
          (rows) =>
              rows.map((row) => _db.driveUploadJobs.map(row.data)).toList(),
        );
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
