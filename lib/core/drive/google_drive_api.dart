// lib/core/drive/google_drive_api.dart
import 'dart:typed_data';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:firecheck/core/drive/drive_api.dart';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as gdrive;

class GoogleDriveApi implements DriveApi {
  GoogleDriveApi({required GoogleSignIn googleSignIn})
      : _googleSignIn = googleSignIn;

  final GoogleSignIn _googleSignIn;

  // Populated during listAssignments() for use in download methods.
  final _fileIdCache = <String, String>{}; // assignmentId → inputZip fileId

  Future<gdrive.DriveApi> _api() async {
    final client = await _googleSignIn.authenticatedClient();
    if (client == null) throw const AuthFailure('Not signed in to Google');
    return gdrive.DriveApi(client);
  }

  @override
  Future<List<DriveAssignment>> listAssignments() async {
    final api = await _api();

    // Locate /firecheck folder
    final firecheckResult = await api.files.list(
      q: "name = 'firecheck' and mimeType = 'application/vnd.google-apps.folder'"
          ' and trashed = false',
      spaces: 'drive',
      $fields: 'files(id)',
    );
    final firecheckId = firecheckResult.files?.firstOrNull?.id;
    if (firecheckId == null) return [];

    // Locate /firecheck/inbox
    final inboxResult = await api.files.list(
      q: "name = 'inbox' and mimeType = 'application/vnd.google-apps.folder'"
          " and '$firecheckId' in parents and trashed = false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    final inboxId = inboxResult.files?.firstOrNull?.id;
    if (inboxId == null) return [];

    // List assignment subfolders
    final foldersResult = await api.files.list(
      q: "mimeType = 'application/vnd.google-apps.folder'"
          " and '$inboxId' in parents and trashed = false",
      spaces: 'drive',
      $fields: 'files(id,name)',
    );

    final assignments = <DriveAssignment>[];
    for (final folder in foldersResult.files ?? <gdrive.File>[]) {
      final folderId = folder.id!;
      final folderName = folder.name!;

      final zipResult = await api.files.list(
        q: "name = 'input.zip' and '$folderId' in parents and trashed = false",
        spaces: 'drive',
        $fields: 'files(id,modifiedTime)',
      );
      final zip = zipResult.files?.firstOrNull;
      if (zip == null) continue;

      final fileId = zip.id!;
      final assignmentId = folderName;
      _fileIdCache[assignmentId] = fileId;

      assignments.add(DriveAssignment(
        assignmentId: assignmentId,
        inputZipFileId: fileId,
        inputZipModifiedTime: zip.modifiedTime!.toIso8601String(),
        driveFolderId: folderId,
      ),);
    }

    return assignments;
  }

  @override
  Future<int> getInputZipSize(String assignmentId) async {
    final fileId = _fileIdCache[assignmentId];
    if (fileId == null) throw const NetworkFailure('Assignment file not cached');
    final api = await _api();
    final meta = await api.files.get(fileId, $fields: 'size') as gdrive.File;
    return int.tryParse(meta.size ?? '0') ?? 0;
  }

  @override
  Stream<DriveDownloadEvent> downloadInputZip(String assignmentId) async* {
    final fileId = _fileIdCache[assignmentId];
    if (fileId == null) throw const NetworkFailure('Assignment file not cached');
    final api = await _api();

    final media = await api.files.get(
      fileId,
      downloadOptions: gdrive.DownloadOptions.fullMedia,
    ) as gdrive.Media;

    final chunks = <int>[];
    var downloaded = 0;
    final total = media.length ?? 0;

    await for (final chunk in media.stream) {
      chunks.addAll(chunk);
      downloaded += chunk.length;
      yield DriveDownloadProgress(downloaded: downloaded, total: total);
    }

    yield DriveDownloadComplete(Uint8List.fromList(chunks));
  }
}
