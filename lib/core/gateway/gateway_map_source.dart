import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:firecheck/core/drive/drive_api.dart';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/gateway/gateway_client.dart';
import 'package:path_provider/path_provider.dart';

class GatewayMapSource implements DriveApi {
  GatewayMapSource(
    this.client, {
    Future<Directory> Function()? temporaryDirectory,
  }) : _directory = temporaryDirectory ?? getTemporaryDirectory;
  final GatewayClient client;
  final Future<Directory> Function() _directory;
  final _manifests = <String, Map<String, dynamic>>{};
  String? _owner;
  // The existing shapefile importer requires all components in memory. Keep a
  // hard bound until it accepts file paths; HTTP download itself goes to disk.
  static const maxBundleBytes = 128 * 1024 * 1024;

  @override
  Future<List<DriveAssignment>> listAssignments() async {
    _owner = client.userId();
    _manifests.clear();
    final result = <DriveAssignment>[];
    String? after;
    do {
      final data = await client.json(
        'GET',
        '/v1/assignments${after == null ? '' : '?after=$after'}',
        owner: _owner,
      );
      for (final item in data['assignments'] as List) {
        final a = item as Map<String, dynamic>;
        final id = a['id'] as String;
        result.add(
          DriveAssignment(
            assignmentId: id,
            localAssignmentId: id,
            inputZipModifiedTime: a['version'] as String,
            driveFolderId: '',
            displayName: a['name'] as String?,
          ),
        );
      }
      after = data['next'] as String?;
    } while (after != null);
    return result;
  }

  Future<Map<String, dynamic>> _manifest(String id) async {
    if (_owner == null || _owner != client.userId()) {
      throw const AuthFailure('Your account changed. Reopen Get Maps.');
    }
    return _manifests[id] ??= await client.json(
      'GET',
      '/v1/assignments/${Uri.encodeComponent(id)}/manifest',
      owner: _owner,
    );
  }

  List<Map<String, dynamic>> _files(Map<String, dynamic> m) =>
      (m['files'] as List).cast<Map<String, dynamic>>();
  @override
  Future<int> getTotalSize(String assignmentId) async {
    final m = await _manifest(assignmentId);
    final total =
        _files(m).fold<int>(0, (sum, f) => sum + (f['size'] as num).toInt());
    if (total <= 0 || total > maxBundleBytes) {
      throw const StorageFailure(
        'This map exceeds the supported 128 MB import size. Contact your supervisor.',
      );
    }
    return total;
  }

  @override
  Stream<DriveDownloadEvent> downloadShapefiles(String assignmentId) async* {
    final m = await _manifest(assignmentId);
    final total = await getTotalSize(assignmentId);
    final result = <String, Uint8List>{};
    final checksums = <String, String>{};
    var downloaded = 0;
    for (final f in _files(m)) {
      final file = await _download(assignmentId, m['version'] as String, f);
      final name = f['name'] as String;
      result[name] = await file.readAsBytes();
      checksums[name] = f['md5'] as String;
      downloaded += result[name]!.length;
      yield DriveDownloadProgress(downloaded: downloaded, total: total);
    }
    yield DriveDownloadComplete(result, checksums);
  }

  Future<File> _download(
    String assignment,
    String version,
    Map<String, dynamic> f,
  ) async {
    final id = f['id'] as String;
    final size = (f['size'] as num).toInt();
    if (![assignment, version, id, _owner!]
            .every((s) => RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(s)) ||
        size <= 0 ||
        size > maxBundleBytes) {
      throw const ValidationFailure('Invalid map manifest.');
    }
    final dir = Directory(
      '${(await _directory()).path}/firecheck-gateway/$_owner/$assignment/$version',
    );
    await dir.create(recursive: true);
    final file = File('${dir.path}/$id.part');
    var offset = file.existsSync() ? await file.length() : 0;
    if (offset > size) {
      await file.delete();
      offset = 0;
    }
    while (offset < size) {
      final end = (offset + 4 * 1024 * 1024 - 1).clamp(0, size - 1);
      final start = offset;
      final response = await client.send(
        'GET',
        '/v1/assignments/$assignment/versions/$version/files/$id',
        owner: _owner,
        headers: {'Range': 'bytes=$offset-$end'},
      );
      if (response.statusCode == 206 &&
          !(response.headers['content-range'] ?? '')
              .startsWith('bytes $offset-$end/$size')) {
        await response.stream.drain<void>();
        throw const NetworkFailure('Invalid download resume response.');
      }
      if (response.statusCode == 200) offset = 0;
      final sink =
          file.openWrite(mode: offset == 0 ? FileMode.write : FileMode.append);
      try {
        await for (final chunk
            in response.stream.timeout(const Duration(seconds: 30))) {
          if (_owner != client.userId()) {
            throw const AuthFailure('Your account changed.');
          }
          offset += chunk.length;
          if (offset > size) {
            throw const ValidationFailure(
              'Map file exceeds its declared size.',
            );
          }
          sink.add(chunk);
          await sink.flush();
        }
      } finally {
        await sink.close();
      }
      if (offset <= start ||
          (response.statusCode == 206 && offset != end + 1)) {
        throw const NetworkFailure('Download interrupted. Retry to resume.');
      }
    }
    final checksum = await md5.bind(file.openRead()).first;
    if (await file.length() != size || checksum.toString() != f['md5']) {
      await file.delete();
      throw const ValidationFailure(
        'The map file failed verification. Retry the download.',
      );
    }
    return file;
  }

  Future<Uint8List?> _sidecar(String id, String name) async {
    final m = await _manifest(id);
    for (final f in _files(m)) {
      if ((f['name'] as String).toLowerCase() == name) {
        return (await _download(id, m['version'] as String, f)).readAsBytes();
      }
    }
    return null;
  }

  @override
  Future<Uint8List?> fetchFieldRequirementsSidecar(String assignmentId) =>
      _sidecar(assignmentId, 'field_requirements.txt');
  @override
  Future<Uint8List?> fetchFormDefinitionSidecar(String assignmentId) =>
      _sidecar(assignmentId, 'form_definition.json');
  @override
  Future<({String folderPath, String folderUrl})> uploadAssignmentFiles({
    required String enumeratorId,
    required String assignmentId,
    required List<({String filename, Uint8List bytes})> files,
  }) async {
    throw const StorageFailure(
      'Use the account-bound upload queue to upload this assignment.',
    );
  }
}
