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

  // Kept for parity with the photo enqueue path that lived here previously;
  // photos now ship to Supabase Storage only, so the field has no current
  // consumer. Keeping the injection avoids churn in provider/test wiring.
  // ignore: unused_field
  final AppDatabase _db;
  final DriveUploadRepository _repo;
  final ShapefileExporter _exporter;
  static const _uuid = Uuid();

  /// Enqueues one Drive upload job per shapefile component (.shp/.shx/.dbf/.prj
  /// per layer). Photos are not uploaded to Drive — they live in Supabase
  /// Storage exclusively.
  ///
  /// Returns the number of new jobs created (0 if already fully enqueued).
  Future<int> execute({required String assignmentId}) async {
    final shapefileExists =
        await _repo.shapefileJobExistsForAssignment(assignmentId);
    if (shapefileExists) return 0;

    final (failure, components) =
        await _exporter.exportToFile(assignmentId: assignmentId);
    if (failure != null || components == null) return 0;

    final capturedAt = DateTime.now();
    var created = 0;
    for (final c in components) {
      final file = File(c.path);
      final size = await file.exists() ? await file.length() : 0;
      await _repo.insertJob(
        id: _uuid.v4(),
        assignmentId: assignmentId,
        filePath: c.path,
        fileType: DriveFileType.shapefile,
        fileName: c.filename,
        fileSizeBytes: size,
        capturedAt: capturedAt,
      );
      created++;
    }
    return created;
  }
}
