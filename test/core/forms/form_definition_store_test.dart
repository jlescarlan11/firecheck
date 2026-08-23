import 'dart:io';
import 'dart:typed_data';

import 'package:firecheck/core/forms/form_definition_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePaths(this.directory);
  final Directory directory;

  @override
  Future<String?> getApplicationDocumentsPath() async => directory.path;
}

void main() {
  late Directory directory;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    directory = await Directory.systemTemp.createTemp('form_definitions_');
    PathProviderPlatform.instance = _FakePaths(directory);
  });

  tearDown(() async => directory.delete(recursive: true));

  test('keeps a version-addressable copy for old offline submissions',
      () async {
    const body = '{"version":"campaign-2026","name":"Campaign"}';
    await writeFormDefinition(Uint8List.fromList(body.codeUnits));
    expect(await readFormDefinition(), body);
    expect(await readFormDefinition(version: 'campaign-2026'), body);
  });

  test('rejects a version that could escape the documents directory', () async {
    const body = '{"version":"../outside","name":"Unsafe"}';
    await expectLater(
      writeFormDefinition(Uint8List.fromList(body.codeUnits)),
      throwsFormatException,
    );
  });
}
