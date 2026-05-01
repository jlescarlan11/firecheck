import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:firecheck/core/sync/shapefile/validation/rules/r1_checksum_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rule = ChecksumRule();
  final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
  final correctMd5 = md5.convert(bytes).toString();

  test('RulePassed when MD5 matches', () {
    final outcome = rule.check({'boundary.shp': bytes}, {'boundary.shp': correctMd5});
    expect(outcome, isA<RulePassed>());
  });

  test('RuleFatal with ruleName checksum when MD5 mismatches', () {
    final corrupted = Uint8List.fromList([...bytes]..[0] ^= 0xFF);
    final outcome = rule.check({'boundary.shp': corrupted}, {'boundary.shp': correctMd5});
    expect(outcome, isA<RuleFatal>());
    expect((outcome as RuleFatal).ruleName, 'checksum');
  });

  test('RulePassed when file not in expectedMd5s (presence checked by R2)', () {
    final outcome = rule.check({'boundary.shp': bytes}, {});
    expect(outcome, isA<RulePassed>());
  });

  test('RuleFatal for second file if first passes but second mismatches', () {
    final corrupted = Uint8List.fromList([...bytes]..[0] ^= 0xFF);
    final outcome = rule.check(
      {'boundary.shp': bytes, 'buildings.shp': corrupted},
      {'boundary.shp': correctMd5, 'buildings.shp': correctMd5},
    );
    expect(outcome, isA<RuleFatal>());
  });
}
