import 'package:image_picker/image_picker.dart';

abstract class CameraService {
  /// Opens the system camera. Returns the captured photo's local path
  /// (full-res), or null if the user cancelled.
  Future<String?> capturePhoto();
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
}

class FakeCameraService implements CameraService {
  FakeCameraService({this.scriptedPath});
  final String? scriptedPath;
  int callCount = 0;

  @override
  Future<String?> capturePhoto() async {
    callCount += 1;
    return scriptedPath;
  }
}
