import 'package:firecheck/core/forms/field_requirements.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseFieldRequirements', () {
    test('empty body falls back to allRequired', () {
      final r = parseFieldRequirements('');
      expect(identical(r, FieldRequirements.allRequired), isTrue);
      expect(r.isRequired('anything'), isTrue);
    });

    test('only comments + blanks falls back to allRequired', () {
      final r = parseFieldRequirements('# header\n\n  # indented\n');
      expect(identical(r, FieldRequirements.allRequired), isTrue);
    });

    test('parses required/optional', () {
      final r = parseFieldRequirements('''
# config
building.buildingName = required
road.widthMeters = optional
''');
      expect(r.isRequired('building.buildingName'), isTrue);
      expect(r.isRequired('road.widthMeters'), isFalse);
    });

    test('tolerates whitespace and case', () {
      final r = parseFieldRequirements('   road.widthMeters   =   OPTIONAL   ');
      expect(r.isRequired('road.widthMeters'), isFalse);
    });

    test('absent keys default to required', () {
      final r = parseFieldRequirements('road.widthMeters = optional');
      expect(r.isRequired('road.somethingElse'), isTrue);
    });

    test('unknown values default to required (typo guard)', () {
      final r = parseFieldRequirements('road.widthMeters = mebbe');
      expect(r.isRequired('road.widthMeters'), isTrue);
    });

    test('ignores lines without = and empty keys', () {
      final r = parseFieldRequirements('not a config line\n = required\nx=optional');
      expect(r.isRequired('x'), isFalse);
    });
  });
}
