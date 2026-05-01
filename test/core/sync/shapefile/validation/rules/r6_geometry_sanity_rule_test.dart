import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/rules/r6_geometry_sanity_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _shp({
  int recordCount = 1,
  double xmin = 1.0,
  double ymin = 2.0,
  double xmax = 3.0,
  double ymax = 4.0,
}) {
  final fileLen = 100 + recordCount * 12;
  final bytes = Uint8List(fileLen);
  final bd = ByteData.sublistView(bytes);
  bd.setUint32(0, 9994, Endian.big);
  bd.setUint32(24, fileLen ~/ 2, Endian.big);
  bd.setFloat64(36, xmin, Endian.little);
  bd.setFloat64(44, ymin, Endian.little);
  bd.setFloat64(52, xmax, Endian.little);
  bd.setFloat64(60, ymax, Endian.little);
  for (var i = 0; i < recordCount; i++) {
    bd.setUint32(100 + i * 12, i + 1, Endian.big);
    bd.setUint32(104 + i * 12, 2, Endian.big);
  }
  return bytes;
}

Map<String, Uint8List> _files({int recordCount = 1, double xmin = 1, double ymin = 2, double xmax = 3, double ymax = 4}) => {
      'boundary.shp': _shp(recordCount: recordCount, xmin: xmin, ymin: ymin, xmax: xmax, ymax: ymax),
      'buildings.shp': _shp(),
      'roads.shp': _shp(),
    };

void main() {
  const rule = GeometrySanityRule();

  test('RulePassed for ≥1 feature with non-degenerate bbox', () {
    expect(rule.check(_files(), {}), isA<RulePassed>());
  });

  test('RuleFatal when all .shp files have 0 records', () {
    final outcome = rule.check(_files(recordCount: 0), {});
    expect(outcome, isA<RuleFatal>());
    expect((outcome as RuleFatal).ruleName, 'geometry_sanity');
  });

  test('RuleFatal when bbox is all zeros (degenerate)', () {
    final outcome = rule.check(_files(xmin: 0, ymin: 0, xmax: 0, ymax: 0), {});
    expect(outcome, isA<RuleFatal>());
  });

  test('RuleFatal when Xmax == Xmin', () {
    final outcome = rule.check(_files(xmin: 1, xmax: 1), {});
    expect(outcome, isA<RuleFatal>());
  });

  test('RuleFatal when Ymax == Ymin', () {
    final outcome = rule.check(_files(ymin: 2, ymax: 2), {});
    expect(outcome, isA<RuleFatal>());
  });
}
