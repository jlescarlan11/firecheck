import 'dart:convert';

import 'package:firecheck/core/forms/form_variant.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_applicability.dart';
import 'package:firecheck/features/survey/road_form/domain/road_form_applicability.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FormVariant.fromJson', () {
    test('parses field-name strings into typed enum sets', () {
      final v = FormVariant.fromJson({
        'id': 'pilot',
        'name': 'Pilot',
        'hideBuildingFields': ['fireFightingFacilities', 'fireLoad'],
        'hideRoadFields': ['othersDescription'],
      });
      expect(v.id, 'pilot');
      expect(v.hideBuildingFields, {
        BuildingFormField.fireFightingFacilities,
        BuildingFormField.fireLoad,
      });
      expect(v.hideRoadFields, {RoadFormField.othersDescription});
    });

    test('unknown field names are dropped rather than throwing', () {
      final v = FormVariant.fromJson({
        'id': 'sloppy',
        'name': 'Sloppy',
        'hideBuildingFields': ['cbmsId', 'NOT_A_FIELD'],
      });
      expect(v.hideBuildingFields, {BuildingFormField.cbmsId});
    });
  });

  group('FormVariantConfig.resolve', () {
    final pilot = FormVariant(
      id: 'pilot',
      name: 'Pilot',
      hideBuildingFields: const {BuildingFormField.fireLoad},
    );
    final cfg = FormVariantConfig(
      variants: {
        'default': FormVariant.defaultVariant,
        'pilot': pilot,
      },
      lguAssignments: const {'CAM-1': 'pilot'},
      enumeratorAssignments: const {'USR-9': 'pilot'},
    );

    test('enumerator assignment wins over LGU', () {
      final v = cfg.resolve(enumeratorId: 'USR-9', lguId: 'OTHER');
      expect(v.id, 'pilot');
    });

    test('LGU assignment used when no enumerator-specific override', () {
      final v = cfg.resolve(enumeratorId: 'someone-else', lguId: 'CAM-1');
      expect(v.id, 'pilot');
    });

    test('falls back to default when no match', () {
      final v = cfg.resolve(enumeratorId: 'x', lguId: 'y');
      expect(v.id, 'default');
    });

    test('stale variant id falls back to default rather than crashing', () {
      final brokenCfg = FormVariantConfig(
        variants: const {'default': FormVariant.defaultVariant},
        lguAssignments: const {'CAM-1': 'nonexistent'},
        enumeratorAssignments: const {},
      );
      final v = brokenCfg.resolve(enumeratorId: null, lguId: 'CAM-1');
      expect(v.id, 'default');
    });
  });

  test('bundled assets/form_variants.json parses cleanly (round-trip)', () {
    const sample = '''
{
  "variants": [
    { "id": "default", "name": "Standard", "hideBuildingFields": [], "hideRoadFields": [] }
  ],
  "assignments": { "lgu": {}, "enumerator": {} }
}
''';
    final cfg = FormVariantConfig.fromJson(
      jsonDecode(sample) as Map<String, dynamic>,
    );
    expect(cfg.variants, contains('default'));
    expect(cfg.resolve().id, 'default');
  });
}
