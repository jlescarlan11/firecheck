import 'dart:io';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_exporter.dart';
import 'package:uuid/uuid.dart';

class EnqueueAssignmentUseCase {
  EnqueueAssignmentUseCase({
    required AppDatabase db,
    required DriveUploadRepository repo,
    required ShapefileExporter exporter,
  })  : _db = db,
        _repo = repo,
        _exporter = exporter;

  final AppDatabase _db;
  final DriveUploadRepository _repo;
  final ShapefileExporter _exporter;
  static const _uuid = Uuid();

  /// Returns the number of new jobs created (0 if already fully enqueued).
  Future<int> execute({required String assignmentId}) async {
    var created = 0;

    // ── Shapefile ────────────────────────────────────────────────────────────
    final shapefileExists =
        await _repo.shapefileJobExistsForAssignment(assignmentId);
    if (!shapefileExists) {
      final (failure, zipPath) =
          await _exporter.exportToFile(assignmentId: assignmentId);
      if (failure == null && zipPath != null) {
        final file = File(zipPath);
        final size = file.existsSync() ? await file.length() : 0;
        await _repo.insertJob(
          id: _uuid.v4(),
          assignmentId: assignmentId,
          filePath: zipPath,
          fileType: DriveFileType.shapefile,
          fileName: zipPath.split('/').last,
          fileSizeBytes: size,
          capturedAt: DateTime.now(),
        );
        created++;
      }
    }

    // ── Photos ───────────────────────────────────────────────────────────────
    final photos = await _photosForAssignment(assignmentId);
    for (final photo in photos) {
      final exists = await _repo.jobExistsForFilePath(photo.localPath);
      if (exists) continue;
      final file = File(photo.localPath);
      final size = file.existsSync() ? await file.length() : 0;
      await _repo.insertJob(
        id: _uuid.v4(),
        assignmentId: assignmentId,
        filePath: photo.localPath,
        fileType: DriveFileType.photo,
        fileName: photo.localPath.split('/').last,
        fileSizeBytes: size,
        capturedAt: photo.capturedAt,
      );
      created++;
    }

    return created;
  }

  Future<List<Photo>> _photosForAssignment(String assignmentId) async {
    final featureIds = await (_db.selectOnly(_db.features)
          ..addColumns([_db.features.id])
          ..where(_db.features.assignmentId.equals(assignmentId)))
        .map((row) => row.read(_db.features.id)!)
        .get();

    if (featureIds.isEmpty) return [];

    final submissionIds = await (_db.selectOnly(_db.submissions)
          ..addColumns([_db.submissions.id])
          ..where(_db.submissions.featureId.isIn(featureIds)))
        .map((row) => row.read(_db.submissions.id)!)
        .get();

    if (submissionIds.isEmpty) return [];

    return (_db.select(_db.photos)
          ..where((t) => t.submissionId.isIn(submissionIds)))
        .get();
  }
}
