import 'package:firecheck/core/photos/camera_service.dart';
import 'package:firecheck/core/photos/image_processor.dart';
import 'package:firecheck/core/photos/photo_capture_controller.dart';
import 'package:firecheck/core/photos/photo_storage_service.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/photo_capture/data/photo_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final cameraServiceProvider = Provider<CameraService>((ref) {
  return ImagePickerCameraService();
});

final imageProcessorProvider = Provider<ImageProcessor>((ref) {
  return const ImageProcessor();
});

final photoStorageProvider = Provider<PhotoStorageService>((ref) {
  return const FilesystemPhotoStorage();
});

final photoRepositoryProvider = Provider<PhotoRepository>((ref) {
  return PhotoRepository(
    db: ref.watch(appDatabaseProvider),
    storage: ref.watch(photoStorageProvider),
  );
});

final photoCaptureControllerProvider = Provider<PhotoCaptureController>((ref) {
  return PhotoCaptureController(
    camera: ref.watch(cameraServiceProvider),
    processor: ref.watch(imageProcessorProvider),
    storage: ref.watch(photoStorageProvider),
    repo: ref.watch(photoRepositoryProvider),
  );
});
