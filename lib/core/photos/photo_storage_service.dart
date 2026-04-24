import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

abstract class PhotoStorageService {
  Future<String> reserveDestPath({required String submissionId});
  Future<void> deleteFile(String path);
}

class FilesystemPhotoStorage implements PhotoStorageService {
  const FilesystemPhotoStorage();

  @override
  Future<String> reserveDestPath({required String submissionId}) async {
    final dir = await getApplicationDocumentsDirectory();
    final subDir = Directory(p.join(dir.path, 'photos', submissionId));
    await subDir.create(recursive: true);
    final id = const Uuid().v4();
    return p.join(subDir.path, '$id.jpg');
  }

  @override
  Future<void> deleteFile(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}

/// In-memory fake — generates deterministic paths under a given root.
class InMemoryPhotoStorage implements PhotoStorageService {
  InMemoryPhotoStorage({String? root}) : _root = root ?? '/tmp/test-photos';

  final String _root;
  int _counter = 0;
  final Set<String> deleted = {};

  @override
  Future<String> reserveDestPath({required String submissionId}) async {
    _counter += 1;
    return p.join(_root, submissionId, 'p$_counter.jpg');
  }

  @override
  Future<void> deleteFile(String path) async {
    deleted.add(path);
  }
}
