import 'package:firecheck/core/drive/drive_upload_api.dart';

class FakeDriveUploadApi implements DriveUploadApi {
  FakeDriveUploadApi({
    this.throwOnUpload = false,
    this.throwOnFolder = false,
  });

  final bool throwOnUpload;
  final bool throwOnFolder;

  final List<String> uploadedPaths = [];
  final Map<String, String> _folderIds = {};
  int _fileCounter = 0;

  @override
  Future<String> createOrGetFolder(String name, String parentId) async {
    if (throwOnFolder) throw Exception('folder creation failed');
    final key = '$parentId/$name';
    return _folderIds[key] ??= 'folder-${_folderIds.length + 1}';
  }

  @override
  Future<String> uploadFile({
    required String localPath,
    required String driveParentId,
    required String fileName,
    String? resumableUri,
    void Function(int sent, int total)? onProgress,
  }) async {
    if (throwOnUpload) throw Exception('upload failed');
    uploadedPaths.add(localPath);
    _fileCounter++;
    onProgress?.call(100, 100);
    return 'drive-file-$_fileCounter';
  }
}
