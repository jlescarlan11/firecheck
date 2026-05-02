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

  // assignmentId → { filename → fileId }
  final _fileCache = <String, Map<String, String>>{};
  final _md5Cache = <String, Map<String, String>>{};

  static const _shapefileExts = {'.shp', '.dbf', '.shx', '.prj'};

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

    // List assignment subfolders — fetch modifiedTime to use as delta key
    final foldersResult = await api.files.list(
      q: "mimeType = 'application/vnd.google-apps.folder'"
          " and '$inboxId' in parents and trashed = false",
      spaces: 'drive',
      $fields: 'files(id,name,modifiedTime)',
    );

    final assignments = <DriveAssignment>[];
    for (final folder in foldersResult.files ?? <gdrive.File>[]) {
      final folderId = folder.id!;
      final folderName = folder.name!;
      final folderModTime = folder.modifiedTime?.toIso8601String();
      if (folderModTime == null) continue;

      // Enumerate shapefile components (.shp, .dbf, .shx, .prj)
      final filesResult = await api.files.list(
        q: "'$folderId' in parents and trashed = false",
        spaces: 'drive',
        $fields: 'files(id,name,md5Checksum)',
      );
      final shapefiles = <String, String>{};
      final md5s = <String, String>{};
      for (final f in filesResult.files ?? <gdrive.File>[]) {
        final name = f.name!;
        final dot = name.lastIndexOf('.');
        final ext = dot >= 0 ? name.substring(dot) : '';
        if (_shapefileExts.contains(ext)) {
          shapefiles[name] = f.id!;
          if (f.md5Checksum != null) md5s[name] = f.md5Checksum!;
        }
      }
      if (shapefiles.isEmpty) continue;

      _fileCache[folderName] = shapefiles;
      _md5Cache[folderName] = md5s;

      assignments.add(DriveAssignment(
        assignmentId: folderName,
        inputZipModifiedTime: folderModTime,
        driveFolderId: folderId,
      ));
    }

    return assignments;
  }

  @override
  Future<int> getTotalSize(String assignmentId) async {
    final files = _fileCache[assignmentId];
    if (files == null) throw const NetworkFailure('Assignment files not cached');
    final api = await _api();
    var total = 0;
    for (final fileId in files.values) {
      final meta = await api.files.get(fileId, $fields: 'size') as gdrive.File;
      total += int.tryParse(meta.size ?? '0') ?? 0;
    }
    return total;
  }

  @override
  Stream<DriveDownloadEvent> downloadShapefiles(String assignmentId) async* {
    final files = _fileCache[assignmentId];
    if (files == null) throw const NetworkFailure('Assignment files not cached');
    final api = await _api();

    final total = await getTotalSize(assignmentId);
    var downloaded = 0;
    final result = <String, Uint8List>{};

    for (final entry in files.entries) {
      final media = await api.files.get(
        entry.value,
        downloadOptions: gdrive.DownloadOptions.fullMedia,
      ) as gdrive.Media;

      final chunks = <int>[];
      await for (final chunk in media.stream) {
        chunks.addAll(chunk);
        downloaded += chunk.length;
        yield DriveDownloadProgress(downloaded: downloaded, total: total);
      }
      result[entry.key] = Uint8List.fromList(chunks);
    }

    yield DriveDownloadComplete(result, _md5Cache[assignmentId] ?? {});
  }
}
