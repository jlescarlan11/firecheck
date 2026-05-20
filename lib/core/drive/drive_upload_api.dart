/// Upload surface for Google Drive. Separate from the read-only DriveApi
/// to keep download and upload concerns independent.
abstract interface class DriveUploadApi {
  /// Returns the Drive folder ID of the shared `firecheck` root, using a
  /// parent-agnostic name search so it converges on the same folder the
  /// download path reads from — including shared-with-me and shared drives.
  /// Creates a new `firecheck` folder in My Drive only if none is visible.
  Future<String> findOrCreateFirecheckRoot();

  /// Returns the Drive folder ID. Queries existing folder first; creates if absent.
  Future<String> createOrGetFolder(String name, String parentId);

  /// Uploads [localPath] into [driveParentId] and returns the Drive file ID.
  ///
  /// [resumableUri] is reserved for future resumable upload support.
  /// It is currently unused by [GoogleDriveUploadApi]; uploads restart on failure.
  Future<String> uploadFile({
    required String localPath,
    required String driveParentId,
    required String fileName,
    String? resumableUri,
    void Function(int sent, int total)? onProgress,
  });
}
