import 'package:firecheck/features/survey/building_form/domain/building_form_state.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BuildingFormState empty() => const BuildingFormState(submissionId: 's1');

  group('validateBuildingForm — does not exist OFF', () {
    test('empty form has all required errors', () {
      final r = validateBuildingForm(empty(), 0);
      expect(
        r.fieldErrors.keys,
        containsAll([
          'photo',
          'buildingName',
          'ra9514Type',
          'storeys',
          'material',
          'cost',
          'fireLoad',
        ]),
      );
      expect(r.isComplete, isFalse);
    });

    test('all required + 1 photo + cost range → complete', () {
      final s = empty().copyWith(
        buildingName: 'Hall',
        ra9514Type: 'A',
        storeys: 2,
        material: 'Concrete',
        costEstimateRange: '500k–1M',
        fireLoad: ['Wood furniture'],
      );
      final r = validateBuildingForm(s, 1);
      expect(r.fieldErrors, isEmpty);
      expect(r.isComplete, isTrue);
    });

    test('cost exact requires positive amount', () {
      final s = empty().copyWith(
        buildingName: 'Hall',
        ra9514Type: 'A',
        storeys: 2,
        material: 'Concrete',
        costIsExact: true,
        costAmount: 0,
        fireLoad: ['Wood furniture'],
      );
      final r = validateBuildingForm(s, 1);
      expect(r.fieldErrors.keys, contains('cost'));
    });

    test('storeys >50 yields a warning, still complete', () {
      final s = empty().copyWith(
        buildingName: 'Tower',
        ra9514Type: 'A',
        storeys: 80,
        material: 'Steel',
        costEstimateRange: '>10M',
        fireLoad: ['Fabric'],
      );
      final r = validateBuildingForm(s, 1);
      expect(r.warnings, contains('storeys_warning_too_tall'));
      expect(r.isComplete, isTrue);
    });
  });

  group('validateBuildingForm — does not exist ON', () {
    test('only photo is required', () {
      final s = empty().copyWith(doesNotExist: true);
      final r = validateBuildingForm(s, 0);
      expect(r.fieldErrors.keys.toList(), ['photo']);
    });

    test('with photo → complete', () {
      final s = empty().copyWith(doesNotExist: true);
      final r = validateBuildingForm(s, 1);
      expect(r.isComplete, isTrue);
    });
  });
}
