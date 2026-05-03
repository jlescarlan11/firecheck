// lib/core/drive/google_drive_upload_api.dart
import 'dart:io';

import 'package:firecheck/core/drive/drive_upload_api.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:googleapis/drive/v3.dart' as gdrive;
import 'package:googleapis_auth/googleapis_auth.dart' as gauth;
import 'package:http/http.dart' as http;

class GoogleDriveUploadApi implements DriveUploadApi {
  GoogleDriveUploadApi({required GoogleAuthRepository googleAuthRepo})
      : _googleAuthRepo = googleAuthRepo;

  final GoogleAuthRepository _googleAuthRepo;

  Future<gdrive.DriveApi> _api() async {
    final token = await _googleAuthRepo.getAccessToken();
    final credentials = gauth.AccessCredentials(
      gauth.AccessToken(
        'Bearer',
        token,
        DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
      null,
      [GoogleAuthRepository.driveFileScope],
    );
    return gdrive.DriveApi(gauth.authenticatedClient(http.Client(), credentials));
  }

  @override
  Future<String> createOrGetFolder(String name, String parentId) async {
    final api = await _api();
    final escapedName = name.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    final escapedParent =
        parentId.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    final existing = await api.files.list(
      q: "name = '$escapedName' "
          "and mimeType = 'application/vnd.google-apps.folder' "
          "and '$escapedParent' in parents "
          "and trashed = false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    final existingId = existing.files?.firstOrNull?.id;
    if (existingId != null) return existingId;

    final folder = await api.files.create(
      gdrive.File()
        ..name = name
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [parentId],
      $fields: 'id',
    );
    final folderId = folder.id;
    if (folderId == null) {
      throw NetworkFailure('Drive did not return id for created folder: $name');
    }
    return folderId;
  }

  @override
  Future<String> uploadFile({
    required String localPath,
    required String driveParentId,
    required String fileName,
    // resumableUri is accepted for interface compatibility but is currently
    // ignored — the googleapis client does not expose a resumable-URI handle
    // in its response, so uploads always restart from the beginning on failure.
    String? resumableUri,
    void Function(int sent, int total)? onProgress,
  }) async {
    final api = await _api();
    final file = File(localPath);
    final fileSize = await file.length();
    final lower = fileName.toLowerCase();
    final mimeType = (lower.endsWith('.jpg') || lower.endsWith('.jpeg'))
        ? 'image/jpeg'
        : lower.endsWith('.png')
            ? 'image/png'
            : 'application/zip';

    final media = gdrive.Media(
      file.openRead(),
      fileSize,
      contentType: mimeType,
    );
    final metadata = gdrive.File()
      ..name = fileName
      ..parents = [driveParentId];

    final created = await api.files.create(
      metadata,
      uploadMedia: media,
      $fields: 'id',
    );
    final fileId = created.id;
    if (fileId == null) {
      throw NetworkFailure('Drive did not return id for uploaded file: $fileName');
    }
    // googleapis does not expose a progress stream for media uploads;
    // onProgress fires once on completion.
    onProgress?.call(fileSize, fileSize);
    return fileId;
  }
}
