import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/rules/r3_header_integrity_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter_test/flutter_test.dart';

// Builds a minimal .shp byte array.
// declaredLengthWords defaults to actualLength / 2 (i.e., correct).
Uint8List _shp({
  int fileCode = 9994,
  int? declaredLengthWords,
  int actualLength = 100,
}) {
  final bytes = Uint8List(actualLength);
  final bd = ByteData.sublistView(bytes);
  bd.setUint32(0, fileCode, Endian.big);
  bd.setUint32(24, declaredLengthWords ?? (actualLength ~/ 2), Endian.big);
  return bytes;
}

Map<String, Uint8List> _filesWithBoundary(Uint8List boundaryShp) => {
      'boundary.shp': boundaryShp,
      'buildings.shp': _shp(),
      'roads.shp': _shp(),
    };

void main() {
  const rule = HeaderIntegrityRule();

  test('RulePassed for valid headers in all three layers', () {
    final files = {
      'boundary.shp': _shp(),
      'buildings.shp': _shp(),
      'roads.shp': _shp(),
    };
    expect(rule.check(files, {}), isA<RulePassed>());
  });

  test('RuleFatal when .shp header is shorter than 100 bytes', () {
    final outcome = rule.check(_filesWithBoundary(Uint8List(50)), {});
    expect(outcome, isA<RuleFatal>());
    expect((outcome as RuleFatal).ruleName, 'header_integrity');
  });

  test('RuleFatal when file code is not 9994', () {
    final outcome = rule.check(_filesWithBoundary(_shp(fileCode: 1234)), {});
    expect(outcome, isA<RuleFatal>());
  });

  test('RuleFatal when declared length * 2 != actual byte length', () {
    // File is 100 bytes but declares 200 bytes (100 words)
    final outcome = rule.check(
      _filesWithBoundary(_shp(declaredLengthWords: 100, actualLength: 100)),
      {},
    );
    expect(outcome, isA<RuleFatal>());
  });

  test('RulePassed when files map has no .shp keys (presence handled by R2)', () {
    expect(rule.check({}, {}), isA<RulePassed>());
  });
}
