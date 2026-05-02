import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/rules/r2_file_set_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Uint8List> _fullFiles() {
  final b = Uint8List.fromList([1]);
  return {
    for (final layer in ['boundary', 'buildings', 'roads'])
      for (final ext in ['.shp', '.dbf', '.shx', '.prj'])
        '$layer$ext': b,
  };
}

void main() {
  const rule = FileSetRule();

  test('RulePassed when all 12 required files present and non-empty', () {
    expect(rule.check(_fullFiles(), {}), isA<RulePassed>());
  });

  test('RuleFatal when a required file is missing', () {
    final files = _fullFiles()..remove('boundary.shp');
    final outcome = rule.check(files, {});
    expect(outcome, isA<RuleFatal>());
    expect((outcome as RuleFatal).ruleName, 'file_set');
  });

  test('RuleFatal when a required file is zero bytes', () {
    final files = _fullFiles()..['buildings.dbf'] = Uint8List(0);
    expect(rule.check(files, {}), isA<RuleFatal>());
  });

  test('RuleWarning when total size exceeds 100 MB', () {
    final files = _fullFiles();
    // Replace one file with 101 MB of bytes to push total over threshold
    files['boundary.shp'] = Uint8List(101 * 1024 * 1024);
    expect(rule.check(files, {}), isA<RuleWarning>());
  });
}
