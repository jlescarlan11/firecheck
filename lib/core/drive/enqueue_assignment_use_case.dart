import 'dart:io';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_exporter.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

class EnqueueAssignmentUseCase {
  EnqueueAssignmentUseCase({
    required AppDatabase db,
    required DriveUploadRepository repo,
    required ShapefileExporter exporter,
    String? Function()? currentUserId,
  })  : _db = db,
        _repo = repo,
        _exporter = exporter,
        _currentUserId = currentUserId;

  final AppDatabase _db;
  final DriveUploadRepository _repo;
  final ShapefileExporter _exporter;
  final String? Function()? _currentUserId;
  static const _uuid = Uuid();

  /// Enqueues one Drive upload job per shapefile component (.shp/.shx/.dbf/.prj
  /// per layer). Photos are not uploaded to Drive — they live in Supabase
  /// Storage exclusively.
  ///
  /// Returns the number of new jobs created (0 if already fully enqueued).
  Future<int> execute({
    required String assignmentId,
    String? expectedOwnerId,
  }) async {
    final activeOwner = _currentUserId?.call();
    final ownerId = expectedOwnerId ?? activeOwner;
    if (expectedOwnerId != null && activeOwner != expectedOwnerId) return 0;
    if (_currentUserId != null && ownerId == null) return 0;

    final (failure, components) =
        await _exporter.exportToFile(assignmentId: assignmentId);
    if (failure != null || components == null) return 0;

    if (_currentUserId != null && _currentUserId() != ownerId) return 0;
    return _db.transaction(() async {
      final existing = await _repo.latestUnfinishedExportBatch(
        assignmentId,
        ownerId: ownerId,
      );
      if (await _sameComponents(existing, components)) return 0;
      final capturedAt = DateTime.now();
      final batchId = _uuid.v4();
      var created = 0;
      for (final c in components) {
        final file = File(c.path);
        final size = file.existsSync() ? await file.length() : 0;
        await _repo.insertJob(
          id: _uuid.v4(),
          assignmentId: assignmentId,
          filePath: c.path,
          fileType: DriveFileType.shapefile,
          fileName: c.filename,
          fileSizeBytes: size,
          capturedAt: capturedAt,
          ownerId: ownerId,
          batchId: batchId,
        );
        created++;
      }
      return created;
    });
  }

  Future<bool> _sameComponents(
    List<DriveUploadJob> existing,
    List<ShapefileComponentFile> components,
  ) async {
    if (existing.isEmpty || existing.length != components.length) return false;
    final byName = {for (final job in existing) job.fileName: job};
    for (final component in components) {
      final job = byName[component.filename];
      if (job == null || !File(job.filePath).existsSync()) return false;
      final before = await File(job.filePath).readAsBytes();
      final after = await File(component.path).readAsBytes();
      // DBF header bytes 1..3 contain the generated update date, not answers.
      // A retry tomorrow remains the same frozen export operation.
      if (component.filename.endsWith('.dbf') &&
          before.length >= 4 &&
          after.length >= 4) {
        before.fillRange(1, 4, 0);
        after.fillRange(1, 4, 0);
      }
      if (!listEquals(before, after)) return false;
    }
    return true;
  }
}
