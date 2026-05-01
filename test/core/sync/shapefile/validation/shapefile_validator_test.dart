import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/shapefile_validator.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter_test/flutter_test.dart';

class _SpyRule extends ShapefileValidationRule {
  _SpyRule(this._outcome);
  final RuleOutcome _outcome;
  var called = false;

  @override
  RuleOutcome check(Map<String, Uint8List> files, Map<String, String> expectedMd5s) {
    called = true;
    return _outcome;
  }
}

void main() {
  test('fail-fast: first RuleFatal stops remaining rules', () {
    final fatal = _SpyRule(const RuleFatal(ruleName: 'test', userMessage: 'err'));
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
}
