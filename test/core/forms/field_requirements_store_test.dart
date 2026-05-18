import 'dart:io';
import 'dart:typed_data';

import 'package:firecheck/core/forms/field_requirements_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.dir);
  final Directory dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;

  @override
  Future<String?> getTemporaryPath() async => dir.path;

  @override
  Future<String?> getApplicationSupportPath() async => dir.path;
}

void main() {
  late Directory dir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    dir = await Directory.systemTemp.createTemp('field_requirements_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(dir);
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('readFieldRequirements returns null when file missing', () async {
    expect(await readFieldRequirements(), isNull);
  });

  test('writeFieldRequirements + readFieldRequirements round-trips', () async {
    await writeFieldRequirements(
      Uint8List.fromList('road.widthMeters = optional'.codeUnits),
    );
    final body = await readFieldRequirements();
    expect(body, contains('road.widthMeters = optional'));
    expect(
      File(p.join(dir.path, fieldRequirementsFilename)).existsSync(),
      isTrue,
    );
  });

  test('clearFieldRequirements removes the file', () async {
    await writeFieldRequirements(Uint8List.fromList('x=y'.codeUnits));
    await clearFieldRequirements();
    expect(await readFieldRequirements(), isNull);
  });
}
