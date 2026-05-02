import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/rules/r7_projection_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _prj(String content) =>
    Uint8List.fromList(content.codeUnits);

Map<String, Uint8List> _withPrj(String prjContent) => {
      'boundary.prj': _prj(prjContent),
      'buildings.prj': _prj(prjContent),
      'roads.prj': _prj(prjContent),
    };

void main() {
  const rule = ProjectionRule();

  test('RulePassed when all .prj files contain 32651', () {
    final files = _withPrj('PROJCS["WGS_1984_UTM_Zone_51N",...,32651,...]');
    expect(rule.check(files, {}), isA<RulePassed>());
  });

  test('RuleWarning when a .prj file is absent', () {
    final outcome = rule.check({}, {});
    expect(outcome, isA<RuleWarning>());
    expect((outcome as RuleWarning).userMessage, contains('Projection'));
  });

  test('RuleFatal when .prj is present but does not contain 32651', () {
    final files = _withPrj('GEOGCS["GCS_WGS_1984",...]');
    final outcome = rule.check(files, {});
    expect(outcome, isA<RuleFatal>());
    expect((outcome as RuleFatal).ruleName, 'projection');
  });

  test('RuleFatal takes precedence: missing prj for boundary but wrong CRS for buildings', () {
    final files = {
      // boundary.prj absent → would be warning
      'buildings.prj': _prj('GEOGCS["GCS_WGS_1984",...]'), // wrong CRS → fatal
      'roads.prj': _prj('...32651...'),
    };
    expect(rule.check(files, {}), isA<RuleFatal>());
  });
}
