import 'dart:io';

import 'package:image_picker/image_picker.dart';

abstract class CameraService {
  /// Opens the system camera. Returns the captured photo's local path
  /// (full-res), or null if the user cancelled.
  Future<String?> capturePhoto();

  /// Retrieves a camera result left behind when Android destroyed the app's
  /// activity. Returns null when there is no recoverable result.
  Future<String?> recoverLostPhoto();
}

class ImagePickerCameraService implements CameraService {
  ImagePickerCameraService([ImagePicker? picker])
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<String?> capturePhoto() async {
    final f = await _picker.pickImage(source: ImageSource.camera);
    return f?.path;
  }

  @override
  Future<String?> recoverLostPhoto() async {
    if (!Platform.isAndroid) return null;
    final response = await _picker.retrieveLostData();
    if (response.isEmpty) return null;
    final exception = response.exception;
    if (exception != null) throw exception;
    return response.file?.path;
  }
}

class FakeCameraService implements CameraService {
  FakeCameraService({this.scriptedPath, this.scriptedLostPath});
  final String? scriptedPath;
  final String? scriptedLostPath;
  int callCount = 0;
  int recoveryCallCount = 0;

  @override
  Future<String?> capturePhoto() async {
    callCount += 1;
    return scriptedPath;
  }

  @override
  Future<String?> recoverLostPhoto() async {
    recoveryCallCount += 1;
    return scriptedLostPath;
  }
}
