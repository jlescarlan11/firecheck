import 'dart:io';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_api.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:intl/intl.dart';

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
  bool _running = false;

  // Session-scoped folder ID cache; not persisted across app restarts.
  final _folderCache = <String, String>{};

  Future<void> drain() async {
    if (_running) return;
    _running = true;
    try {
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
    } on Exception catch (e) {
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
    final assignment = await (db.select(db.assignments)
          ..where((t) => t.id.equals(job.assignmentId)))
        .getSingle();
    final enumeratorId = assignment.enumeratorId;
    final dateKey = DateFormat('yyyy-MM-dd').format(job.capturedAt);
    final subfolderName =
        job.fileType == DriveFileType.photo ? 'photos' : 'shapefiles';

    final cacheKey = '$enumeratorId/$dateKey/$subfolderName';
    if (_folderCache.containsKey(cacheKey)) {
      return _folderCache[cacheKey]!;
    }

    final enumeratorFolderId =
        await api.createOrGetFolder(enumeratorId, rootFolderId);
    final dateFolderId =
        await api.createOrGetFolder(dateKey, enumeratorFolderId);
    final subFolderId =
        await api.createOrGetFolder(subfolderName, dateFolderId);

    _folderCache[cacheKey] = subFolderId;
    return subFolderId;
  }

  DateTime? _nextRetryAt(int attempts) {
    final base = DateTime.now();
    return switch (attempts) {
      1 => base.add(const Duration(seconds: 30)),
      2 => base.add(const Duration(minutes: 2)),
      _ => null,
    };
  }
}
