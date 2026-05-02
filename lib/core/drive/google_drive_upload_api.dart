// lib/core/drive/google_drive_upload_api.dart
import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:firecheck/core/drive/drive_upload_api.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as gdrive;

class GoogleDriveUploadApi implements DriveUploadApi {
  GoogleDriveUploadApi({required GoogleSignIn googleSignIn})
      : _googleSignIn = googleSignIn;

  final GoogleSignIn _googleSignIn;

  Future<gdrive.DriveApi> _api() async {
    final client = await _googleSignIn.authenticatedClient();
    if (client == null) throw const AuthFailure('Not signed in to Google');
    return gdrive.DriveApi(client);
  }

  @override
  Future<String> createOrGetFolder(String name, String parentId) async {
    final api = await _api();
    final existing = await api.files.list(
      q: "name = '$name' "
          "and mimeType = 'application/vnd.google-apps.folder' "
          "and '$parentId' in parents "
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
      throw AuthFailure('Drive did not return id for created folder: $name');
    }
    return folderId;
  }

  @override
  Future<String> uploadFile({
    required String localPath,
    required String driveParentId,
    required String fileName,
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
      throw AuthFailure('Drive did not return id for uploaded file: $fileName');
    }
    // googleapis does not expose a progress stream for media uploads;
    // onProgress fires once on completion.
    onProgress?.call(fileSize, fileSize);
    return fileId;
  }
}
