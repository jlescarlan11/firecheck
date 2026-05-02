import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/rules/r4_index_consistency_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter_test/flutter_test.dart';

// Each .shp content record: 8-byte header + 4 bytes null shape = 12 bytes = 6 words.
const _contentWords = 2; // 4 bytes / 2
const _recordBytes = 12; // 8 header + 4 content

Uint8List _shpBytes(int recordCount) {
  final fileLen = 100 + recordCount * _recordBytes;
  final bytes = Uint8List(fileLen);
  final bd = ByteData.sublistView(bytes);
  bd.setUint32(0, 9994, Endian.big);
  bd.setUint32(24, fileLen ~/ 2, Endian.big);
  for (var i = 0; i < recordCount; i++) {
    final off = 100 + i * _recordBytes;
    bd.setUint32(off, i + 1, Endian.big);        // record number (1-based)
    bd.setUint32(off + 4, _contentWords, Endian.big); // content length
    bd.setUint32(off + 8, 0, Endian.little);     // null shape
  }
  return bytes;
}

Uint8List _shxBytes(int recordCount, {int? badOffsetAtIndex}) {
  final fileLen = 100 + recordCount * 8;
  final bytes = Uint8List(fileLen);
  final bd = ByteData.sublistView(bytes);
  bd.setUint32(0, 9994, Endian.big);
  bd.setUint32(24, fileLen ~/ 2, Endian.big);
  for (var i = 0; i < recordCount; i++) {
    final offsetWords = (100 + i * _recordBytes) ~/ 2;
    final offset = (i == badOffsetAtIndex) ? 999999 : offsetWords;
    bd.setUint32(100 + i * 8, offset, Endian.big);
    bd.setUint32(104 + i * 8, _contentWords, Endian.big);
  }
  return bytes;
}

Map<String, Uint8List> _files({
  int shpCount = 2,
  int shxCount = 2,
  int? badOffsetAtIndex,
}) =>
    {
      'boundary.shp': _shpBytes(shpCount),
      'boundary.shx': _shxBytes(shxCount, badOffsetAtIndex: badOffsetAtIndex),
      'buildings.shp': _shpBytes(shpCount),
      'buildings.shx': _shxBytes(shxCount),
      'roads.shp': _shpBytes(shpCount),
      'roads.shx': _shxBytes(shxCount),
    };

void main() {
  const rule = IndexConsistencyRule();

  test('RulePassed when .shx count matches .shp count and offsets are valid', () {
    expect(rule.check(_files(), {}), isA<RulePassed>());
  });

  test('RuleFatal when .shx record count exceeds .shp record count', () {
    final outcome = rule.check(_files(shpCount: 2, shxCount: 3), {});
    expect(outcome, isA<RuleFatal>());
    expect((outcome as RuleFatal).ruleName, 'index_consistency');
  });

  test('RuleFatal when .shx record count is less than .shp record count', () {
    final outcome = rule.check(_files(shpCount: 2, shxCount: 1), {});
    expect(outcome, isA<RuleFatal>());
  });

  test('RuleFatal when a .shx offset points outside .shp byte range', () {
    final outcome = rule.check(_files(badOffsetAtIndex: 0), {});
    expect(outcome, isA<RuleFatal>());
  });
}
