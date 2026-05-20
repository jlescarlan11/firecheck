import 'dart:io';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_api.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';

class DriveUploadWorker {
  DriveUploadWorker({
    required this.api,
    required this.repo,
    required this.db,
    required this.enumeratorIdentifier,
  });

  final DriveUploadApi api;
  final DriveUploadRepository repo;
  final AppDatabase db;
  /// Resolves the per-enumerator Drive folder name. Typically the user's
  /// email so multi-user uploads stay segregated in the shared output/
  /// tree. Sync so each `_processOne` can read it without an extra await.
  /// Returning null falls back to a generic 'unknown-enumerator' folder.
  final String? Function() enumeratorIdentifier;

  static const _maxConcurrent = 3;
  // NOTE: This guard is not isolate-safe. Background WorkManager isolates
  // have their own instance of this worker. resetStuckUploadingToPending()
  // in drain() provides the actual safety net against duplicate processing.
  bool _running = false;

  // Session-scoped folder ID cache; not persisted across app restarts.
  final _folderCache = <String, Future<String>>{};
  // The shared firecheck root is resolved once per session via a
  // parent-agnostic name lookup — same discovery the download path uses —
  // so uploads always land in the folder downloads read from.
  Future<String>? _firecheckRootFuture;

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
    // Drive layout for enumerator-produced shapefile components:
    //   firecheck/output/<enumerator>/<folderName>/  ← buildings.{shp,dbf,shx,prj}, roads.*
    //
    // The `output/` subtree is created entirely by this app, which keeps
    // every file under it within reach of the `drive.file` OAuth scope
    // (writes restricted to app-created files). The base map sitting at
    // firecheck/input/<folderName>/ remains untouched — it was uploaded
    // by the admin's Drive client and not owned by enumerators.
    //
    // The per-enumerator layer prevents two enumerators uploading the
    // same assignment from creating files with identical names in the
    // same parent folder — both would be visible to the admin via the
    // Drive UI, but the drive.file scope blocks one app instance from
    // touching another instance's files. Per-enumerator subfolders make
    // each submission addressable.
    //
    // folderName is the human-readable Drive folder ("cebu"), not the
    // canonical Supabase UUID — keeps the output hierarchy aligned with
    // how downloads name the assignment.
    final cacheKey = job.assignmentId;
    if (_folderCache.containsKey(cacheKey)) return _folderCache[cacheKey]!;
    // Set the cache entry synchronously — before any await — so concurrent
    // jobs in the same drain pass share one folder-resolution Future
    // instead of each independently creating duplicate output/ and
    // <assignment>/ folders in Drive (the bug that left three "output"
    // folders behind on the first attempt).
    final future = Future<String>(() async {
      final folderName = await _resolveDriveFolderName(job.assignmentId);
      return _createFolderHierarchy(folderName);
    });
    _folderCache[cacheKey] = future.then(
      (id) => id,
      onError: (Object e, StackTrace s) {
        _folderCache.remove(cacheKey);
        return Future<String>.error(e, s);
      },
    );
    return _folderCache[cacheKey]!;
  }

  Future<String> _resolveDriveFolderName(String assignmentId) async {
    final row = await (db.select(db.assignments)
          ..where((t) => t.id.equals(assignmentId)))
        .getSingleOrNull();
    return row?.name ?? assignmentId;
  }

  Future<String> _resolveFirecheckRoot() {
    return _firecheckRootFuture ??= api.findOrCreateFirecheckRoot().then(
      (id) => id,
      onError: (Object e, StackTrace s) {
        _firecheckRootFuture = null;
        return Future<String>.error(e, s);
      },
    );
  }

  Future<String> _createFolderHierarchy(String assignmentFolderName) async {
    final firecheckRootId = await _resolveFirecheckRoot();
    final outputId = await api.createOrGetFolder('output', firecheckRootId);
    final enumeratorFolderName =
        _sanitizeFolderName(enumeratorIdentifier()) ?? 'unknown-enumerator';
    final enumeratorId =
        await api.createOrGetFolder(enumeratorFolderName, outputId);
    return api.createOrGetFolder(assignmentFolderName, enumeratorId);
  }

  /// Replaces characters that aren't safe in Drive folder names (mainly the
  /// slash) with `_`. Returns null on empty/null input so callers can apply
  /// their own fallback.
  String? _sanitizeFolderName(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.replaceAll(RegExp(r'[\\/]'), '_').trim();
    return cleaned.isEmpty ? null : cleaned;
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
