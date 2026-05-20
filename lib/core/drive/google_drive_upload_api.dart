// lib/core/drive/google_drive_upload_api.dart
import 'dart:io';

import 'package:firecheck/core/drive/drive_upload_api.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:googleapis/drive/v3.dart' as gdrive;
import 'package:googleapis_auth/googleapis_auth.dart' as gauth;
import 'package:http/http.dart' as http;

class GoogleDriveUploadApi implements DriveUploadApi {
  GoogleDriveUploadApi({required GoogleTokenSource googleAuthRepo})
      : _googleAuthRepo = googleAuthRepo;

  final GoogleTokenSource _googleAuthRepo;

  Future<gdrive.DriveApi> _api() async {
    final token = await _googleAuthRepo.getAccessToken();
    final credentials = gauth.AccessCredentials(
      gauth.AccessToken(
        'Bearer',
        token,
        DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
      null,
      [GoogleTokenSource.driveFileScope],
    );
    return gdrive.DriveApi(gauth.authenticatedClient(http.Client(), credentials));
  }

  @override
  Future<String> findOrCreateFirecheckRoot() async {
    // Parent-agnostic lookup mirrors GoogleDriveApi.listAssignments so the
    // upload path lands in the same folder downloads read from — including
    // shared-with-me and shared-drive layouts where the folder lives
    // outside the user's My Drive root. Only creates a new folder in
    // My Drive if none is visible to the user anywhere.
    final api = await _api();
    final result = await api.files.list(
      q: "name = 'firecheck'"
          " and mimeType = 'application/vnd.google-apps.folder'"
          ' and trashed = false',
      spaces: 'drive',
      $fields: 'files(id)',
    );
    final existingId = result.files?.firstOrNull?.id;
    if (existingId != null) return existingId;

    final folder = await api.files.create(
      gdrive.File()
        ..name = 'firecheck'
        ..mimeType = 'application/vnd.google-apps.folder',
      $fields: 'id',
    );
    final folderId = folder.id;
    if (folderId == null) {
      throw NetworkFailure('Drive did not return id for created firecheck root');
    }
    return folderId;
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
            : 'application/octet-stream';

    final media = gdrive.Media(
      file.openRead(),
      fileSize,
      contentType: mimeType,
    );

    // Overwrite-in-place: shapefile components for the same assignment land
    // at stable paths (/firecheck/<assignmentId>/buildings.shp, etc.), so a
    // plain files.create would accumulate duplicate siblings and break the
    // documented "last upload wins" contract on [DriveApi]. Photos are
    // expected to use unique filenames, so the lookup is a no-op for them
    // in practice.
    final escapedName =
        fileName.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    final escapedParent =
        driveParentId.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    final existing = await api.files.list(
      q: "name = '$escapedName'"
          " and '$escapedParent' in parents"
          ' and trashed = false',
      spaces: 'drive',
      $fields: 'files(id)',
    );
    final existingId = existing.files?.firstOrNull?.id;

    final String? fileId;
    if (existingId != null) {
      final updated = await api.files.update(
        gdrive.File()..name = fileName,
        existingId,
        uploadMedia: media,
        $fields: 'id',
      );
      fileId = updated.id;
    } else {
      final metadata = gdrive.File()
        ..name = fileName
        ..parents = [driveParentId];
      final created = await api.files.create(
        metadata,
        uploadMedia: media,
        $fields: 'id',
      );
      fileId = created.id;
    }
    if (fileId == null) {
      throw NetworkFailure('Drive did not return id for uploaded file: $fileName');
    }
    // googleapis does not expose a progress stream for media uploads;
    // onProgress fires once on completion.
    onProgress?.call(fileSize, fileSize);
    return fileId;
  }
}
