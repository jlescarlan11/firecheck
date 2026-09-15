import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/shapefile_validator.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter_test/flutter_test.dart';

class _SpyRule extends ShapefileValidationRule {
  _SpyRule(this._outcome);
  final RuleOutcome _outcome;
  var called = false;

  @override
  RuleOutcome check(
      Map<String, Uint8List> files, Map<String, String> expectedMd5s) {
    called = true;
    return _outcome;
  }
}

void main() {
  test('a download with no map geometry cannot be imported', () {
    final report = ShapefileValidator().validate({}, {}, relaxedMode: true);
    expect(report.hasFatals, isTrue);
  });

  test(
      'readable mode still rejects corrupt geometry under an arbitrary layer name',
      () {
    final report = ShapefileValidator()
        .validate({'custom_parcels.shp': Uint8List(12)}, {}, relaxedMode: true);
    expect(report.hasFatals, isTrue);
    expect(report.fatal!.ruleName, 'header_integrity');
  });
  test(
      'readable mode allows missing survey columns but rejects damaged attributes',
      () {
    final schema = ShapefileValidator(rules: [
      _SpyRule(const RuleFatal(
          ruleName: 'attribute_schema', userMessage: 'Missing columns'))
    ]).validate({}, {}, relaxedMode: true);
    expect(schema.hasFatals, isFalse);
    expect(schema.hasWarnings, isTrue);
    final damaged = ShapefileValidator(rules: [
      _SpyRule(const RuleFatal(
          ruleName: 'attribute_integrity', userMessage: 'Corrupt table'))
    ]).validate({}, {}, relaxedMode: true);
    expect(damaged.hasFatals, isTrue);
  });

  test('fail-fast: first RuleFatal stops remaining rules', () {
    final fatal =
        _SpyRule(const RuleFatal(ruleName: 'test', userMessage: 'err'));
    final never = _SpyRule(const RulePassed());
    final report = ShapefileValidator(rules: [fatal, never]).validate({}, {});
    expect(report.hasFatals, isTrue);
    expect(report.fatal!.ruleName, 'test');
    expect(never.called, isFalse);
  });

  test('warnings accumulate when no fatals', () {
    final w1 = _SpyRule(const RuleWarning(userMessage: 'w1'));
    final w2 = _SpyRule(const RuleWarning(userMessage: 'w2'));
    final report = ShapefileValidator(rules: [w1, w2]).validate({}, {});
    expect(report.hasFatals, isFalse);
    expect(report.warnings, hasLength(2));
  });

  test('clean path: all rules pass', () {
    final report = ShapefileValidator(rules: [
      _SpyRule(const RulePassed()),
      _SpyRule(const RulePassed()),
    ]).validate({}, {});
    expect(report.isClean, isTrue);
  });

  test('warning before fatal: fatal is still returned', () {
    final warning = _SpyRule(const RuleWarning(userMessage: 'w'));
    final fatal = _SpyRule(const RuleFatal(ruleName: 'r', userMessage: 'err'));
    final report = ShapefileValidator(rules: [warning, fatal]).validate({}, {});
    expect(report.hasFatals, isTrue);
    expect(report.warnings, hasLength(1));
  });

  test('default constructor includes all 7 production rules (smoke test)', () {
    // Passes empty files — R2 will fatal on missing files. Just verify it runs without error.
    final report = ShapefileValidator().validate({}, {});
    expect(report.hasFatals, isTrue); // R2 should fatal: missing files
  });

  test('relaxed mode demotes missing layers to a visible warning', () {
    final shp = Uint8List(100);
    final header = ByteData.sublistView(shp);
    header.setUint32(0, 9994, Endian.big);
    header.setUint32(24, 50, Endian.big);
    final report = ShapefileValidator()
        .validate({'custom.shp': shp}, {}, relaxedMode: true);

    expect(report.hasFatals, isFalse);
    expect(report.warnings, isNotEmpty);
    expect(
      report.warnings.any((warning) => warning.userMessage.contains('missing')),
      isTrue,
    );
  });
}
