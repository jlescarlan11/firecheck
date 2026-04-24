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
    // Best-effort: swallow PathNotFoundException so the caller doesn't have
    // to know whether the file existed. avoid_slow_async_io flags
    // File.exists(); we just attempt the delete and ignore the miss.
    try {
      await File(path).delete();
    } on FileSystemException {
      // File didn't exist — fine.
    }
  }
}

/// In-memory fake — generates deterministic paths and creates the parent
/// directory so consumers (e.g. ImageProcessor) can immediately write the
/// file. Matches FilesystemPhotoStorage's contract that the directory
/// exists by the time reserveDestPath returns.
class InMemoryPhotoStorage implements PhotoStorageService {
  InMemoryPhotoStorage({String? root}) : _root = root ?? '/tmp/test-photos';

  final String _root;
  int _counter = 0;
  final Set<String> deleted = {};

  @override
  Future<String> reserveDestPath({required String submissionId}) async {
    _counter += 1;
    final subDir = Directory(p.join(_root, submissionId));
    await subDir.create(recursive: true);
    return p.join(subDir.path, 'p$_counter.jpg');
  }

  @override
  Future<void> deleteFile(String path) async {
    deleted.add(path);
  }
}
