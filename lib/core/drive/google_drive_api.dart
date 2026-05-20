// lib/core/drive/google_drive_api.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:firecheck/core/drive/drive_api.dart';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as gdrive;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class GoogleDriveApi implements DriveApi {
  GoogleDriveApi({required GoogleTokenSource googleAuthRepo})
      : _googleAuthRepo = googleAuthRepo;

  final GoogleTokenSource _googleAuthRepo;
  static const _uuid = Uuid();
  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static String _toLocalId(String folderName) {
    if (_uuidPattern.hasMatch(folderName)) return folderName;
    return _uuid.v5(Namespace.url.value, folderName);
  }

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
  // Optional sidecar that pins the canonical Supabase UUID for this assignment.
  // When present its content overrides the UUID-v5 derivation from the folder
  // name, so a human-readable folder like "cebu" can map to the exact UUID the
  // admin created in Supabase (e.g. 00000000-0000-0000-0000-000000000a01).
  static const _assignmentIdFilename = 'assignment_id.txt';

  Future<gdrive.DriveApi> _api() async {
    final token = await _googleAuthRepo.getAccessToken();
    final credentials = AccessCredentials(
      AccessToken(
        'Bearer',
        token,
        DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
      null,
      [GoogleTokenSource.driveReadonlyScope, GoogleTokenSource.driveFileScope],
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

    // Locate the input/ subfolder where admin-uploaded base maps live.
    // Drive layout:
    //   firecheck/input/<assignment>/<base-map files>      ← downloads read here
    //   firecheck/output/<assignment>/<enumerator files>   ← uploads write here
    // The split keeps the enumerator-written subtree (which the app owns
    // under drive.file scope) cleanly separate from the admin's base map.
    final inputResult = await api.files.list(
      q: "name = 'input' and mimeType = 'application/vnd.google-apps.folder'"
          " and '$firecheckId' in parents and trashed = false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    final inputId = inputResult.files?.firstOrNull?.id;
    if (inputId == null) return [];

    // Assignments live directly inside firecheck/input/<assignment>/.
    final foldersResult = await api.files.list(
      q: "mimeType = 'application/vnd.google-apps.folder'"
          " and '$inputId' in parents and trashed = false",
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
      String? assignmentIdFileId;
      for (final f in filesResult.files ?? <gdrive.File>[]) {
        final name = f.name!;
        final lowerName = name.toLowerCase();
        final dot = name.lastIndexOf('.');
        final ext = dot >= 0 ? name.substring(dot).toLowerCase() : '';
        final isShapefile = _shapefileExts.contains(ext);
        final isConfig = lowerName == _configFilename;
        if (isShapefile || isConfig) {
          shapefiles[name] = f.id!;
          if (f.md5Checksum != null) md5s[name] = f.md5Checksum!;
          sizes[name] = int.tryParse(f.size ?? '0') ?? 0;
        } else if (lowerName == _assignmentIdFilename) {
          assignmentIdFileId = f.id!;
        }
      }
      if (shapefiles.isEmpty) continue;

      // Read the canonical Supabase UUID from assignment_id.txt if present.
      String? pinnedLocalId;
      if (assignmentIdFileId != null) {
        try {
          final media = await api.files.get(
            assignmentIdFileId,
            downloadOptions: gdrive.DownloadOptions.fullMedia,
          ) as gdrive.Media;
          final bytes = <int>[];
          await for (final chunk in media.stream) {
            bytes.addAll(chunk);
          }
          final raw = utf8.decode(bytes).trim().toLowerCase();
          if (_uuidPattern.hasMatch(raw)) pinnedLocalId = raw;
        } catch (_) {}
      }

      _fileCache[folderName] = shapefiles;
      _md5Cache[folderName] = md5s;
      _sizeCache[folderName] = sizes;

      final localId = pinnedLocalId ?? _toLocalId(folderName);
      debugPrint(
        '[DriveApi] folder "$folderName" → localAssignmentId=$localId'
        '${pinnedLocalId != null ? " (pinned from assignment_id.txt)" : localId != folderName ? " (v5 derived)" : ""}',
      );
      assignments.add(
        DriveAssignment(
          assignmentId: folderName,
          localAssignmentId: localId,
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

    // Target: firecheck/output/<assignment_id>/<file>. Mirrors the
    // worker's queue-based layout so both Drive upload paths land in the
    // same subtree, distinct from the admin's read-only firecheck/input/
    // base-map tree. Conflict safety is handled at the database layer
    // via submit_attribution_with_conflict_check + resolve_attribution.
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
    final outputId = await _findOrCreateFolder(api, firecheckId, 'output');
    final assignmentFolderId =
        await _findOrCreateFolder(api, outputId, assignmentId);

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
      folderPath: 'firecheck/output/$assignmentId/',
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
