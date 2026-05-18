import 'dart:io';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_api.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';

class DriveUploadWorker {
  DriveUploadWorker({
    required this.api,
    required this.repo,
    required this.db,
    required this.rootFolderId,
  });

  final DriveUploadApi api;
  final DriveUploadRepository repo;
  final AppDatabase db;
  final String rootFolderId;

  static const _maxConcurrent = 3;
  // NOTE: This guard is not isolate-safe. Background WorkManager isolates
  // have their own instance of this worker. resetStuckUploadingToPending()
  // in drain() provides the actual safety net against duplicate processing.
  bool _running = false;

  // Session-scoped folder ID cache; not persisted across app restarts.
  final _folderCache = <String, Future<String>>{};

  Future<void> drain() async {
    if (_running) return;
    _running = true;
    try {
      await repo.resetStuckUploadingToPending();
      while (true) {
        final jobs = await repo.getPendingJobs();
        if (jobs.isEmpty) return;
        await Future.wait(jobs.take(_maxConcurrent).map(_processOne));
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _processOne(DriveUploadJob job) async {
    final file = File(job.filePath);
    if (!file.existsSync()) {
      await repo.markDead(job.id, reason: 'file missing: ${job.filePath}');
      return;
    }

    await repo.markUploading(job.id);

    try {
      final parentId = await _resolveParentFolder(job);
      final driveFileId = await api.uploadFile(
        localPath: job.filePath,
        driveParentId: parentId,
        fileName: job.fileName,
        resumableUri: job.resumableUri,
      );
      await repo.markCompleted(job.id, driveFileId: driveFileId);
    } on Object catch (e) {
      final attempts = job.retryCount + 1;
      final next = _nextRetryAt(attempts);
      if (next == null) {
        await repo.markDead(job.id, reason: e.toString());
      } else {
        await repo.markFailed(
          job.id,
          reason: e.toString(),
          retryCount: attempts,
          nextRetryAt: next,
        );
      }
    }
  }

  Future<String> _resolveParentFolder(DriveUploadJob job) async {
    // Unified Drive layout per assignment:
    //   <rootFolderId>/<assignmentId>/                  ← shapefile zips overwrite here
    //   <rootFolderId>/<assignmentId>/photos/           ← photos (unique filenames, no overwrite)
    // Conflict safety for shapefile overwrites is handled at the DB
    // layer via submit_attribution_with_conflict_check; Drive is the
    // file mirror, not the source of truth for attributions.
    final isPhoto = job.fileType == DriveFileType.photo;
    final cacheKey = isPhoto ? '${job.assignmentId}/photos' : job.assignmentId;
    if (_folderCache.containsKey(cacheKey)) return _folderCache[cacheKey]!;
    // Store only successful results; remove on failure so retries hit Drive again.
    _folderCache[cacheKey] = _createFolderHierarchy(job.assignmentId, isPhoto)
        .then(
      (id) => id,
      onError: (Object e, StackTrace s) {
        _folderCache.remove(cacheKey);
        return Future<String>.error(e, s);
      },
    );
    return _folderCache[cacheKey]!;
  }

  Future<String> _createFolderHierarchy(
    String assignmentId,
    bool isPhoto,
  ) async {
    final assignmentFolderId =
        await api.createOrGetFolder(assignmentId, rootFolderId);
    if (!isPhoto) return assignmentFolderId;
    return api.createOrGetFolder('photos', assignmentFolderId);
  }

  DateTime? _nextRetryAt(int attempts) {
    final base = DateTime.now();
    return switch (attempts) {
      1 => base.add(const Duration(seconds: 30)),
      2 => base.add(const Duration(minutes: 2)),
      3 => base.add(const Duration(minutes: 10)),
      _ => null,
    };
  }
}
