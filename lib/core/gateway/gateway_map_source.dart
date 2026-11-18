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
    final owner = client.userId();
    if (owner == null) throw const AuthFailure('Please sign in to FireCheck.');
    _owner = owner;
    _manifests.clear();
    final result = <DriveAssignment>[];
    String? after;
    do {
      final data = await client.json(
        'GET',
        '/v1/assignments${after == null ? '' : '?after=$after'}',
        owner: owner,
      );
      _ensureOwner(owner);
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

  String _operationOwner() {
    final owner = _owner;
    if (owner == null) {
      throw const AuthFailure('Your account changed. Reopen Get Maps.');
    }
    _ensureOwner(owner);
    return owner;
  }

  void _ensureOwner(String owner) {
    if (owner != _owner || owner != client.userId()) {
      throw const AuthFailure('Your account changed. Reopen Get Maps.');
    }
  }

  Future<Map<String, dynamic>> _manifest(String id, String owner) async {
    _ensureOwner(owner);
    final cached = _manifests[id];
    if (cached != null) return cached;
    final manifest = await client.json(
      'GET',
      '/v1/assignments/${Uri.encodeComponent(id)}/manifest',
      owner: owner,
    );
    _ensureOwner(owner);
    return _manifests[id] = manifest;
  }

  List<Map<String, dynamic>> _files(Map<String, dynamic> m) =>
      (m['files'] as List).cast<Map<String, dynamic>>();

  int _totalSize(Map<String, dynamic> manifest) {
    var total = 0;
    for (final file in _files(manifest)) {
      final size = (file['size'] as num).toInt();
      if (size <= 0) throw const ValidationFailure('Invalid map manifest.');
      total += size;
    }
    if (total <= 0 || total > maxBundleBytes) {
      throw const StorageFailure(
        'This map exceeds the supported 128 MB import size. Contact your supervisor.',
      );
    }
    return total;
  }

  @override
  Future<int> getTotalSize(String assignmentId) async =>
      _totalSize(await _manifest(assignmentId, _operationOwner()));

  @override
  Stream<DriveDownloadEvent> downloadShapefiles(String assignmentId) async* {
    final owner = _operationOwner();
    final m = await _manifest(assignmentId, owner);
    final total = _totalSize(m);
    final result = <String, Uint8List>{};
    final checksums = <String, String>{};
    var verifiedBytes = 0;
    for (final f in _files(m)) {
      await for (final range
          in _download(owner, assignmentId, m['version'] as String, f)) {
        _ensureOwner(owner);
        if (!range.verified) {
          final downloaded = verifiedBytes + range.downloaded;
          yield DriveDownloadProgress(
            downloaded: downloaded,
            total: total,
            verifying: downloaded == total,
          );
        } else {
          final name = f['name'] as String;
          result[name] = await range.file.readAsBytes();
          _ensureOwner(owner);
          checksums[name] = f['md5'] as String;
          verifiedBytes += result[name]!.length;
        }
      }
    }
    _ensureOwner(owner);
    yield DriveDownloadComplete(result, checksums);
  }

  // The generator yields only after flushing bytes to disk. Pausing the outer
  // subscription applies backpressure here; cancellation closes the sink and
  // cancels the HTTP stream before any subsequent range is requested.
  Stream<({File file, int downloaded, bool verified})> _download(
    String owner,
    String assignment,
    String version,
    Map<String, dynamic> f,
  ) async* {
    _ensureOwner(owner);
    final id = f['id'] as String;
    final size = (f['size'] as num).toInt();
    if (![assignment, version, id, owner]
            .every((s) => RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(s)) ||
        size <= 0 ||
        size > maxBundleBytes) {
      throw const ValidationFailure('Invalid map manifest.');
    }
    final file = await _partialFile(owner, assignment, version, id);
    _ensureOwner(owner);
    var offset = file.existsSync() ? await file.length() : 0;
    if (offset > size) {
      await file.delete();
      offset = 0;
    }
    if (offset > 0) yield (file: file, downloaded: offset, verified: false);
    while (offset < size) {
      _ensureOwner(owner);
      final end = _rangeEnd(offset, size);
      final start = offset;
      final response = await client.send(
        'GET',
        '/v1/assignments/$assignment/versions/$version/files/$id',
        owner: owner,
        headers: {'Range': 'bytes=$offset-$end'},
      );
      if (response.statusCode != 200 && response.statusCode != 206 ||
          response.statusCode == 206 &&
              response.headers['content-range'] != 'bytes $offset-$end/$size') {
        // A rejected body may never finish. Cancel its subscription instead
        // of waiting for EOF before reporting the invalid range.
        await response.stream.listen(null).cancel();
        throw const NetworkFailure('Invalid download resume response.');
      }
      if (response.statusCode == 200) offset = 0;
      final sink =
          file.openWrite(mode: offset == 0 ? FileMode.write : FileMode.append);
      try {
        await for (final chunk
            in response.stream.timeout(const Duration(seconds: 30))) {
          _ensureOwner(owner);
          offset += chunk.length;
          if (offset > size) {
            throw const ValidationFailure(
              'Map file exceeds its declared size.',
            );
          }
          sink.add(chunk);
          await sink.flush();
          _ensureOwner(owner);
          yield (file: file, downloaded: offset, verified: false);
        }
      } finally {
        await sink.close();
      }
      _ensureOwner(owner);
      if (offset <= (response.statusCode == 200 ? 0 : start) ||
          (response.statusCode == 200 && offset != size) ||
          (response.statusCode == 206 && offset != end + 1)) {
        throw const NetworkFailure('Download interrupted. Retry to resume.');
      }
    }
    _ensureOwner(owner);
    final checksum = await md5.bind(file.openRead()).first;
    _ensureOwner(owner);
    if (await file.length() != size || checksum.toString() != f['md5']) {
      _ensureOwner(owner);
      await file.delete();
      throw const ValidationFailure(
        'The map file failed verification. Retry the download.',
      );
    }
    _ensureOwner(owner);
    yield (file: file, downloaded: size, verified: true);
  }

  int _rangeEnd(int offset, int size) =>
      (offset + 4 * 1024 * 1024 - 1).clamp(0, size - 1);

  Future<File> _partialFile(
    String owner,
    String assignment,
    String version,
    String id,
  ) async {
    final root = await _directory();
    _ensureOwner(owner);
    final dir =
        Directory('${root.path}/firecheck-gateway/$owner/$assignment/$version');
    await dir.create(recursive: true);
    return File('${dir.path}/$id.part');
  }

  Future<Uint8List?> _sidecar(String id, String name) async {
    final owner = _operationOwner();
    final m = await _manifest(id, owner);
    for (final f in _files(m)) {
      if ((f['name'] as String).toLowerCase() == name) {
        await for (final range
            in _download(owner, id, m['version'] as String, f)) {
          if (range.verified) {
            final bytes = await range.file.readAsBytes();
            _ensureOwner(owner);
            return bytes;
          }
        }
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
