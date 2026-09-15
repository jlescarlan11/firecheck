import 'package:firecheck/core/photos/camera_service.dart';
import 'package:firecheck/core/photos/image_processor.dart';
import 'package:firecheck/core/photos/pending_photo_capture_store.dart';
import 'package:firecheck/core/photos/photo_storage_service.dart';
import 'package:firecheck/features/survey/photo_capture/data/photo_repository.dart';

class PhotoCaptureController {
  PhotoCaptureController({
    required this.camera,
    required this.processor,
    required this.storage,
    required this.repo,
    required this.pendingStore,
  });

  final CameraService camera;
  final ImageProcessor processor;
  final PhotoStorageService storage;
  final PhotoRepository repo;
  final PendingPhotoCaptureStore pendingStore;

  /// Open camera → user shoots → resize + EXIF copy → insert Drift row.
  /// Returns null if user cancelled. Returns the new photo id on success.
  Future<String?> capture({
    required String submissionId,
    required String featureId,
  }) async {
    // Do not overwrite the only recovered ImagePicker result with a new
    // camera context. A later camera attempt first completes the retained
    // recovery; if it still cannot persist, the retained source remains for
    // another retry.
    final retained = await pendingStore.read();
    if (retained?.recoveredSourcePath case final sourcePath?) {
      final id = await _persist(
        sourcePath: sourcePath,
        submissionId: retained!.submissionId,
      );
      await pendingStore.clear();
      return id;
    }

    await pendingStore.save(
      PendingPhotoCapture(
        submissionId: submissionId,
        featureId: featureId,
      ),
    );
    final String? src;
    try {
      src = await camera.capturePhoto();
    } on Object {
      await pendingStore.clear();
      rethrow;
    }
    if (src == null) {
      await pendingStore.clear();
      return null;
    }
    try {
      final id = await _persist(sourcePath: src, submissionId: submissionId);
      await pendingStore.clear();
      return id;
    } on Object {
      await pendingStore.clear();
      rethrow;
    }
  }

  /// Consumes ImagePicker's Android lost-data slot and attaches the recovered
  /// image to the durable submission context saved before camera launch.
  /// Returns the durable capture context so the UI can restore the exact form
  /// and submission tab that owned the camera launch.
  Future<PendingPhotoCapture?> recoverPendingCapture() async {
    final pending = await pendingStore.read();
    if (pending == null) return null;
    final src = pending.recoveredSourcePath ?? await camera.recoverLostPhoto();
    if (src == null) {
      await pendingStore.clear();
      return null;
    }
    // ImagePicker exposes lost data only once. Retain the recovered path
    // before processing so a transient filesystem/DB failure can be retried
    // on the next bootstrap instead of silently discarding the photo.
    final retained = PendingPhotoCapture(
      submissionId: pending.submissionId,
      featureId: pending.featureId,
      recoveredSourcePath: src,
    );
    await pendingStore.save(retained);
    await _persist(sourcePath: src, submissionId: pending.submissionId);
    await pendingStore.clear();
    return pending;
  }

  Future<String> _persist({
    required String sourcePath,
    required String submissionId,
  }) async {
    final submission = await (repo.db.select(repo.db.submissions)
          ..where((t) => t.id.equals(submissionId)))
        .getSingleOrNull();
    if (submission == null) {
      throw StateError('Cannot attach a photo to a missing submission.');
    }
    final dest = await storage.reserveDestPath(submissionId: submissionId);
    final gps = await processor.resizeAndCopyExif(
      sourcePath: sourcePath,
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
