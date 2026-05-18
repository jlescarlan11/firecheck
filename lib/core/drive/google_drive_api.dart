// lib/core/drive/google_drive_api.dart
import 'dart:typed_data';

import 'package:firecheck/core/drive/drive_api.dart';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:googleapis/drive/v3.dart' as gdrive;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;

class GoogleDriveApi implements DriveApi {
  GoogleDriveApi({required GoogleAuthRepository googleAuthRepo})
      : _googleAuthRepo = googleAuthRepo;

  final GoogleAuthRepository _googleAuthRepo;

  // assignmentId → { filename → fileId }
  final _fileCache = <String, Map<String, String>>{};
  final _md5Cache = <String, Map<String, String>>{};
  // assignmentId → { filename → sizeBytes }
  final _sizeCache = <String, Map<String, int>>{};

  static const _shapefileExts = {'.shp', '.dbf', '.shx', '.prj'};
  // Sidecar config the enumerator can drop next to the shapefile to control
  // form-field validation without a rebuild (Issue #43). Matched by exact
  // filename, case-insensitive.
  static const _configFilename = 'field_requirements.txt';

  Future<gdrive.DriveApi> _api() async {
    final token = await _googleAuthRepo.getAccessToken();
    final credentials = AccessCredentials(
      AccessToken(
        'Bearer',
        token,
        DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
      null,
      [GoogleAuthRepository.driveReadonlyScope, GoogleAuthRepository.driveFileScope],
    );
    return gdrive.DriveApi(authenticatedClient(http.Client(), credentials));
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

    // Assignments live directly inside /firecheck/<assignment_id>/.
    // (Previously /firecheck/inbox/<assignment_id>/ — the inbox layer was
    // dropped in favour of a single shared assignment folder that holds
    // both the base map and any per-user uploads.)
    final foldersResult = await api.files.list(
      q: "mimeType = 'application/vnd.google-apps.folder'"
          " and '$firecheckId' in parents and trashed = false",
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
        $fields: 'files(id,name,md5Checksum,size)',
      );
      final shapefiles = <String, String>{};
      final md5s = <String, String>{};
      final sizes = <String, int>{};
      for (final f in filesResult.files ?? <gdrive.File>[]) {
        final name = f.name!;
        final dot = name.lastIndexOf('.');
        final ext = dot >= 0 ? name.substring(dot).toLowerCase() : '';
        final isShapefile = _shapefileExts.contains(ext);
        final isConfig = name.toLowerCase() == _configFilename;
        if (isShapefile || isConfig) {
          shapefiles[name] = f.id!;
          if (f.md5Checksum != null) md5s[name] = f.md5Checksum!;
          sizes[name] = int.tryParse(f.size ?? '0') ?? 0;
        }
      }
      if (shapefiles.isEmpty) continue;

      _fileCache[folderName] = shapefiles;
      _md5Cache[folderName] = md5s;
      _sizeCache[folderName] = sizes;

      assignments.add(
        DriveAssignment(
          assignmentId: folderName,
          inputZipModifiedTime: folderModTime,
          driveFolderId: folderId,
        ),
      );
    }

    return assignments;
  }

  @override
  Future<int> getTotalSize(String assignmentId) async {
    final sizes = _sizeCache[assignmentId];
    if (sizes == null) throw const NetworkFailure('Assignment files not cached');
    return sizes.values.fold<int>(0, (acc, s) => acc + s);
  }

  @override
  Stream<DriveDownloadEvent> downloadShapefiles(String assignmentId) async* {
    final files = _fileCache[assignmentId];
    if (files == null) throw const NetworkFailure('Assignment files not cached');
    final api = await _api();

    final sizes = _sizeCache[assignmentId] ?? {};
    final total = sizes.values.fold<int>(0, (acc, s) => acc + s);
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

  @override
  Future<Uint8List?> fetchFieldRequirementsSidecar(String assignmentId) async {
    final files = _fileCache[assignmentId];
    if (files == null) return null;
    String? fileId;
    for (final entry in files.entries) {
      if (entry.key.toLowerCase() == _configFilename) {
        fileId = entry.value;
        break;
      }
    }
    if (fileId == null) return null;
    final api = await _api();
    final media = await api.files.get(
      fileId,
      downloadOptions: gdrive.DownloadOptions.fullMedia,
    ) as gdrive.Media;
    final chunks = <int>[];
    await for (final chunk in media.stream) {
      chunks.addAll(chunk);
    }
    return Uint8List.fromList(chunks);
  }

  @override
  Future<({String folderPath, String folderUrl})> uploadAssignmentFiles({
    required String enumeratorId,
    required String assignmentId,
    required List<({String filename, Uint8List bytes})> files,
  }) async {
    final api = await _api();

    // Target: /firecheck/<assignment_id>/<file>. Same folder downloads
    // read from; conflict safety is handled at the database layer via
    // submit_attribution_with_conflict_check + resolve_attribution.
    // Files with the same name overwrite the prior version (latest
    // upload wins); photos use unique filenames so they accumulate.
    // enumeratorId is preserved on the signature for callers but is
    // no longer part of the Drive path.
    //
    // The 'firecheck' root is discovered using the same parent-agnostic
    // query as [listAssignments] so uploads target the shared folder
    // even when it lives outside the user's My Drive root (e.g.
    // shared-with-me or a shared drive). Otherwise downloads and
    // uploads would diverge to different folder trees.
    final firecheckId = await _findOrCreateFirecheckRoot(api);
    final assignmentFolderId =
        await _findOrCreateFolder(api, firecheckId, assignmentId);

    for (final file in files) {
      final media = gdrive.Media(
        Stream.value(file.bytes),
        file.bytes.length,
      );

      // Overwrite-in-place: if a file with this name already exists in
      // the assignment folder, update its content rather than creating
      // a duplicate.
      final existing = await api.files.list(
        q: "name = '${file.filename.replaceAll("'", "\\'")}'"
            " and '$assignmentFolderId' in parents"
            " and trashed = false",
        spaces: 'drive',
        $fields: 'files(id)',
      );
      final existingId = existing.files?.firstOrNull?.id;
      if (existingId != null) {
        await api.files.update(
          gdrive.File()..name = file.filename,
          existingId,
          uploadMedia: media,
        );
      } else {
        await api.files.create(
          gdrive.File()
            ..name = file.filename
            ..parents = [assignmentFolderId],
          uploadMedia: media,
        );
      }
    }

    return (
      folderPath: 'firecheck/$assignmentId/',
      folderUrl:
          'https://drive.google.com/drive/folders/$assignmentFolderId',
    );
  }

  Future<String> _findOrCreateFolder(
    gdrive.DriveApi api,
    String parentId,
    String name,
  ) async {
    final escapedName = name.replaceAll("'", "\\'");
    final result = await api.files.list(
      q: "name = '$escapedName'"
          " and mimeType = 'application/vnd.google-apps.folder'"
          " and trashed = false"
          " and '$parentId' in parents",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    if (result.files?.isNotEmpty == true) {
      return result.files!.first.id!;
    }
    final folder = await api.files.create(
      gdrive.File()
        ..name = name
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [parentId],
    );
    return folder.id!;
  }

  /// Mirrors the parent-agnostic 'firecheck' lookup used by
  /// [listAssignments] so uploads land in the same folder that downloads
  /// read from — including shared-with-me or shared-drive layouts where
  /// the folder is not in the user's My Drive root. Only creates a new
  /// folder in My Drive root if none is visible to the user anywhere.
  Future<String> _findOrCreateFirecheckRoot(gdrive.DriveApi api) async {
    final result = await api.files.list(
      q: "name = 'firecheck'"
          " and mimeType = 'application/vnd.google-apps.folder'"
          " and trashed = false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    final existingId = result.files?.firstOrNull?.id;
    if (existingId != null) return existingId;
    final folder = await api.files.create(
      gdrive.File()
        ..name = 'firecheck'
        ..mimeType = 'application/vnd.google-apps.folder',
    );
    return folder.id!;
  }
}
