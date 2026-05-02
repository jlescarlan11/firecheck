import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/rules/r5_attribute_integrity_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _dbf({int recordCount = 1, List<String> fieldNames = const ['feat_id']}) {
  final headerSize = 32 + fieldNames.length * 32 + 1; // +1 for 0x0D
  final bytes = Uint8List(headerSize);
  final bd = ByteData.sublistView(bytes);
  bytes[0] = 0x03; // version
  bd.setInt32(4, recordCount, Endian.little);
  bd.setInt16(8, headerSize, Endian.little);
  for (var i = 0; i < fieldNames.length; i++) {
    final base = 32 + i * 32;
    final name = fieldNames[i];
    for (var j = 0; j < name.length && j < 11; j++) {
      bytes[base + j] = name.codeUnitAt(j);
    }
    bytes[base + 11] = 0x43; // type 'C'
    bytes[base + 16] = 10;   // field length
  }
  bytes[32 + fieldNames.length * 32] = 0x0D; // terminator
  return bytes;
}

// Build a minimal .shp with exactly recordCount records (null shapes)
Uint8List _shp(int recordCount) {
  final fileLen = 100 + recordCount * 12;
  final bytes = Uint8List(fileLen);
  final bd = ByteData.sublistView(bytes);
  bd.setUint32(0, 9994, Endian.big);
  bd.setUint32(24, fileLen ~/ 2, Endian.big);
  for (var i = 0; i < recordCount; i++) {
    bd.setUint32(100 + i * 12, i + 1, Endian.big);
    bd.setUint32(104 + i * 12, 2, Endian.big);
  }
  return bytes;
}

Map<String, Uint8List> _validFiles() => {
      'boundary.shp': _shp(2),
      'boundary.dbf': _dbf(recordCount: 2, fieldNames: ['feat_id']),
      'buildings.shp': _shp(2),
      'buildings.dbf': _dbf(
        recordCount: 2,
        fieldNames: ['feat_id', 'bldg_use', 'bldg_type'],
      ),
      'roads.shp': _shp(2),
      'roads.dbf': _dbf(recordCount: 2, fieldNames: ['feat_id', 'road_type']),
    };

void main() {
  const rule = AttributeIntegrityRule();

  test('RulePassed for valid DBF files with matching counts and required columns', () {
    expect(rule.check(_validFiles(), {}), isA<RulePassed>());
  });

  test('RuleFatal when DBF header is shorter than 32 bytes', () {
    final files = _validFiles()..['buildings.dbf'] = Uint8List(16);
    expect(rule.check(files, {}), isA<RuleFatal>());
    expect((rule.check(files, {}) as RuleFatal).ruleName, 'attribute_integrity');
  });

  test('RuleFatal when DBF version byte is not 0x03 or 0x83', () {
    final badDbf = _dbf(recordCount: 2, fieldNames: ['feat_id', 'bldg_use', 'bldg_type']);
    badDbf[0] = 0x02; // invalid version
    final files = _validFiles()..['buildings.dbf'] = badDbf;
    expect(rule.check(files, {}), isA<RuleFatal>());
  });

  test('RuleFatal when DBF record count does not match .shp record count', () {
    final files = _validFiles()
      ..['buildings.dbf'] = _dbf(
        recordCount: 99, // does not match _shp(2)
        fieldNames: ['feat_id', 'bldg_use', 'bldg_type'],
      );
    expect(rule.check(files, {}), isA<RuleFatal>());
  });

  test('RuleFatal when buildings.dbf is missing required column bldg_use', () {
    final files = _validFiles()
      ..['buildings.dbf'] = _dbf(
        recordCount: 2,
        fieldNames: ['feat_id', 'bldg_type'], // missing bldg_use
      );
    expect(rule.check(files, {}), isA<RuleFatal>());
  });

  test('RuleFatal when roads.dbf is missing required column road_type', () {
    final files = _validFiles()
      ..['roads.dbf'] = _dbf(
        recordCount: 2,
        fieldNames: ['feat_id'], // missing road_type
      );
    expect(rule.check(files, {}), isA<RuleFatal>());
  });
}
