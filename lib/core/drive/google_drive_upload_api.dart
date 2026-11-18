// lib/core/drive/google_drive_upload_api.dart
import 'dart:io';

import 'package:firecheck/core/drive/drive_upload_api.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:googleapis/drive/v3.dart' as gdrive;
import 'package:googleapis_auth/googleapis_auth.dart' as gauth;
import 'package:http/http.dart' as http;

class GoogleDriveUploadApi implements DriveUploadApi {
  GoogleDriveUploadApi({
    required GoogleTokenSource googleAuthRepo,
    http.Client? httpClient,
  })  : _googleAuthRepo = googleAuthRepo,
        _httpClient = httpClient;

  final http.Client? _httpClient;

  final GoogleTokenSource _googleAuthRepo;

  gdrive.DriveApi? _boundApi;
  String? _boundAccount;

  Future<void> _checkAccount(String accountId) async {
    try {
      if (!await _googleAuthRepo.isSignedIn() ||
          await _googleAuthRepo.getEnumeratorId() != accountId) {
        throw const DriveAccountChanged();
      }
    } on AuthFailure {
      throw const DriveAccountChanged();
    }
  }

  @override
  Future<DriveUploadApi> forAccount(String accountId) async {
    await _checkAccount(accountId);
    final token = await _googleAuthRepo.getAccessToken();
    await _checkAccount(accountId);
    final authenticated = gauth.authenticatedClient(
      _httpClient ?? http.Client(),
      _credentials(token),
    );
    return GoogleDriveUploadApi(
      googleAuthRepo: _googleAuthRepo,
      httpClient: _httpClient,
    )
      .._boundAccount = accountId
      .._boundApi = gdrive.DriveApi(
        _AccountCheckedClient(authenticated, () => _checkAccount(accountId)),
      );
  }

  Future<gdrive.DriveApi> _api() async {
    final account = _boundAccount;
    if (account == null || _boundApi == null) {
      throw StateError('Bind the Drive account before uploading.');
    }
    await _checkAccount(account);
    return _boundApi!;
  }

  gauth.AccessCredentials _credentials(String token) => gauth.AccessCredentials(
        gauth.AccessToken(
          'Bearer',
          token,
          DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
        null,
        [GoogleTokenSource.driveFileScope],
      );

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
      throw const NetworkFailure(
        'Drive did not return id for created firecheck root',
      );
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
          'and trashed = false',
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

    var sent = 0;
    onProgress?.call(0, fileSize);
    final media = gdrive.Media(
      file.openRead().map((chunk) {
        sent += chunk.length;
        onProgress?.call(sent, fileSize);
        return chunk;
      }),
      fileSize,
      contentType: mimeType,
    );

    // Overwrite-in-place: shapefile components for the same assignment land
    // at stable paths (/firecheck/<assignmentId>/buildings.shp, etc.), so a
    // plain files.create would accumulate duplicate siblings and break the
    // documented "last upload wins" contract on [DriveApi]. Photos are
    // expected to use unique filenames, so the lookup is a no-op for them
    // in practice.
    final escapedName = fileName.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
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
      throw NetworkFailure(
        'Drive did not return id for uploaded file: $fileName',
      );
    }
    // The worker marks completion only after this server response.
    onProgress?.call(fileSize, fileSize);
    return fileId;
  }
}

class _AccountCheckedClient extends http.BaseClient {
  _AccountCheckedClient(this._inner, this._check);
  final http.Client _inner;
  final Future<void> Function() _check;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await _check();
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
