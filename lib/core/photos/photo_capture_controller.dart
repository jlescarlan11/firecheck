import 'package:firecheck/core/photos/camera_service.dart';
import 'package:firecheck/core/photos/image_processor.dart';
import 'package:firecheck/core/photos/photo_storage_service.dart';
import 'package:firecheck/features/survey/photo_capture/data/photo_repository.dart';

class PhotoCaptureController {
  PhotoCaptureController({
    required this.camera,
    required this.processor,
    required this.storage,
    required this.repo,
  });

  final CameraService camera;
  final ImageProcessor processor;
  final PhotoStorageService storage;
  final PhotoRepository repo;

  /// Open camera → user shoots → resize + EXIF copy → insert Drift row.
  /// Returns null if user cancelled. Returns the new photo id on success.
  Future<String?> capture({required String submissionId}) async {
    final src = await camera.capturePhoto();
    if (src == null) return null;
    final dest = await storage.reserveDestPath(submissionId: submissionId);
    final gps = await processor.resizeAndCopyExif(
      sourcePath: src,
      destPath: dest,
    );
    return repo.insert(
      submissionId: submissionId,
      localPath: dest,
      capturedAt: DateTime.now(),
      gpsLat: gps.lat,
      gpsLng: gps.lng,
    );
  }
}
