import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

Future<Directory> useTemporaryFormDirectory() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previous = PathProviderPlatform.instance;
  final directory = await Directory.systemTemp.createTemp('firecheck_forms_');
  PathProviderPlatform.instance = _Paths(directory.path);
  addTearDown(() async {
    PathProviderPlatform.instance = previous;
    await directory.delete(recursive: true);
  });
  return directory;
}
