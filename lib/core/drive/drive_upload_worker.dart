import 'dart:io';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_api.dart';
import 'package:firecheck/core/drive/drive_upload_process_identity.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/upload_transfer_progress.dart';
import 'package:firecheck/core/errors/failure.dart';

class DriveUploadWorker {
  DriveUploadWorker({
    required this.api,
    required this.repo,
    required this.db,
    required this.enumeratorIdentifier,
    required this.currentUserId,
    this.gatewayDrain,
    this.progress,
    Future<String?> Function()? processIdentity,
  }) : _processIdentity = processIdentity ?? resolveDriveUploadProcessIdentity;

  final Future<String?> Function() _processIdentity;
  final DriveUploadApi? api;
  final UploadTransferTracker? progress;
  final Future<void> Function()? gatewayDrain;
  final DriveUploadRepository repo;
  final AppDatabase db;

  /// Resolves the per-enumerator Drive folder name. Typically the user's
  /// email so multi-user uploads stay segregated in the shared output/
  /// tree. Captured once alongside the original account before any await.
  /// Returning null falls back to that account's identifier.
  final String? Function() enumeratorIdentifier;
  final String? Function() currentUserId;

  void _checkAccount(String accountId) {
    if (currentUserId() != accountId || _sessionAborted) {
      throw const DriveAccountChanged();
    }
  }

  static const _maxConcurrent = 3;
  // This flag only coalesces this instance. SQLite claims and persisted
  // process ownership protect overlapping foreground/headless workers.
  bool _running = false;
  bool _sessionAborted = false;

  // Session-scoped folder ID cache; not persisted across app restarts.
  final _folderCache = <String, Future<String>>{};
  // The shared firecheck root is resolved once per session via a
  // parent-agnostic name lookup — same discovery the download path uses —
  // so uploads always land in the folder downloads read from.
  Future<String>? _firecheckRootFuture;

  void _clearFolderCache() {
    _folderCache.clear();
    _firecheckRootFuture = null;
  }

  Future<void> drain() async {
    if (gatewayDrain != null) return gatewayDrain!();
    if (_running) return;
    final accountId = currentUserId();
    if (accountId == null || accountId.isEmpty) return;
    final identifier = enumeratorIdentifier() ?? accountId;
    _running = true;
    _sessionAborted = false;
    progress?.clear();
    try {
      final processIdentity = await _processIdentity();
      _checkAccount(accountId);
      if (processIdentity == null || processIdentity.isEmpty) return;
      final boundApi = await api!.forAccount(accountId);
      _checkAccount(accountId);
      _clearFolderCache();
      await repo.resetStuckUploadingToPending(
        ownerId: accountId,
        processIdentity: processIdentity,
      );
      _checkAccount(accountId);
      while (currentUserId() == accountId && !_sessionAborted) {
        final jobs = await repo.getPendingJobs(
          limit: _maxConcurrent,
          ownerId: accountId,
        );
        _checkAccount(accountId);
        if (jobs.isEmpty) return;
        await Future.wait(
          jobs.map(
            (job) => _processOne(
              job,
              boundApi,
              accountId,
              identifier,
              processIdentity,
            ),
          ),
        );
      }
    } on DriveAccountChanged {
      // Original-owner work remains pending for that account's next session.
    } on AuthFailure {
      // No usable credential was acquired; leave the original queue intact.
    } finally {
      _running = false;
    }
  }

  Future<void> _processOne(
    DriveUploadJob job,
    DriveUploadApi boundApi,
    String accountId,
    String identifier,
    String processIdentity,
  ) async {
    _checkAccount(accountId);
    if (job.ownerId != accountId) return;
    if (!await repo.claimForUpload(
      job.id,
      ownerId: accountId,
      processIdentity: processIdentity,
    )) {
      return;
    }
    final file = File(job.filePath);
    if (!file.existsSync()) {
      await repo.markDead(job.id, reason: 'file missing: ${job.filePath}');
      return;
    }

    progress?.update(job, 0, TransferPhase.uploading);

    try {
      _checkAccount(accountId);
      final parentId = await _resolveParentFolder(job, boundApi, identifier);
      _checkAccount(accountId);
      final driveFileId = await boundApi.uploadFile(
        localPath: job.filePath,
        driveParentId: parentId,
        fileName: job.fileName,
        resumableUri: job.resumableUri,
        onProgress: (sent, total) => progress?.update(
          job,
          sent,
          sent >= total ? TransferPhase.confirming : TransferPhase.uploading,
        ),
      );
      _checkAccount(accountId);
      await repo.markCompleted(job.id, driveFileId: driveFileId);
      progress?.update(job, job.fileSizeBytes, TransferPhase.completed);
    } on DriveAccountChanged {
      _sessionAborted = true;
      await repo.releaseForAccountChange(job.id, accountId);
    } on Object catch (e) {
      await _recordFailure(job, e);
    }
  }

  Future<void> _recordFailure(DriveUploadJob job, Object e) async {
    progress?.update(job, progress?.sentFor(job.id) ?? 0, TransferPhase.failed);
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

  Future<String> _resolveParentFolder(
    DriveUploadJob job,
    DriveUploadApi boundApi,
    String identifier,
  ) async {
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
      return _createFolderHierarchy(folderName, boundApi, identifier);
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

  Future<String> _resolveFirecheckRoot(DriveUploadApi boundApi) {
    return _firecheckRootFuture ??= boundApi.findOrCreateFirecheckRoot().then(
      (id) => id,
      onError: (Object e, StackTrace s) {
        _firecheckRootFuture = null;
        return Future<String>.error(e, s);
      },
    );
  }

  Future<String> _createFolderHierarchy(
    String assignmentFolderName,
    DriveUploadApi boundApi,
    String identifier,
  ) async {
    final firecheckRootId = await _resolveFirecheckRoot(boundApi);
    final outputId =
        await boundApi.createOrGetFolder('output', firecheckRootId);
    final enumeratorFolderName =
        _sanitizeFolderName(identifier) ?? 'unknown-enumerator';
    final enumeratorId =
        await boundApi.createOrGetFolder(enumeratorFolderName, outputId);
    return boundApi.createOrGetFolder(assignmentFolderName, enumeratorId);
  }

  /// Replaces characters that aren't safe in Drive folder names (mainly the
  /// slash) with `_`. Returns null on empty/null input so callers can apply
  /// their own fallback.
  String? _sanitizeFolderName(String? raw) => sanitizeDriveFolderName(raw);

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

/// Replaces characters that aren't safe in Drive folder names (mainly the
/// slash) with `_`. Returns null on empty/null input so callers can apply
/// their own fallback. Shared with FinalizeAssignmentUploadUseCase so the
/// path persisted on the assignment row matches the path the worker
/// actually writes to.
String? sanitizeDriveFolderName(String? raw) {
  if (raw == null) return null;
  final cleaned = raw.replaceAll(RegExp(r'[\\/]'), '_').trim();
  return cleaned.isEmpty ? null : cleaned;
}
