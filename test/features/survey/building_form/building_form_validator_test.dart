import 'package:firecheck/core/forms/field_requirements.dart';
import 'package:firecheck/core/forms/form_definition.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_applicability.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_state.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BuildingFormState empty() => const BuildingFormState(submissionId: 's1');

  test('configured required CBMS and facilities block missing answers', () {
    final requirements = parseFieldRequirements(
      'building.cbmsId=required\nbuilding.fireFightingFacilities=required',
    );
    expect(
      validateBuildingForm(empty(), 1, requirements: requirements).fieldErrors,
      containsPair('cbmsId', 'required'),
    );
    expect(
      validateBuildingForm(empty(), 1, requirements: requirements).fieldErrors,
      containsPair('fireFightingFacilities', 'required'),
    );
    final answered = empty().copyWith(
      cbmsId: 'local / arbitrary ID',
      fireFightingFacilities: ['None'],
    );
    final result =
        validateBuildingForm(answered, 1, requirements: requirements);
    expect(result.fieldErrors, isNot(contains('cbmsId')));
    expect(result.fieldErrors, isNot(contains('fireFightingFacilities')));
    expect(
      validateBuildingForm(
        empty().copyWith(doesNotExist: true),
        1,
        requirements: requirements,
      ).isComplete,
      isTrue,
    );
  });

  test('required hidden fields and whitespace CBMS use applicability policy',
      () {
    final requirements = parseFieldRequirements(
      'building.cbmsId=required\nbuilding.fireFightingFacilities=required',
    );
    final state = empty().copyWith(cbmsId: '  ');
    expect(
      validateBuildingForm(state, 1, requirements: requirements).fieldErrors,
      containsPair('cbmsId', 'required'),
    );
    final result = validateBuildingForm(
      state,
      1,
      requirements: requirements,
      hidden: {
        BuildingFormField.cbmsId,
        BuildingFormField.fireFightingFacilities,
      },
    );
    expect(result.fieldErrors, isNot(contains('cbmsId')));
    expect(result.fieldErrors, isNot(contains('fireFightingFacilities')));
  });

  test('explicit optional fields accept unanswered values', () {
    final result = validateBuildingForm(
      empty(),
      1,
      requirements: parseFieldRequirements(
        'building.cbmsId=optional\nbuilding.fireFightingFacilities=optional',
      ),
    );
    expect(result.fieldErrors, isNot(contains('cbmsId')));
    expect(result.fieldErrors, isNot(contains('fireFightingFacilities')));
  });

  for (final section in ['identity', 'fireFightingFacilities']) {
    test('definition-hidden $section skips its required new answer', () {
      final hiddenField =
          section == 'identity' ? 'cbmsId' : 'fireFightingFacilities';
      final definition = FormDefinition.fromJson({
        'version': 'visibility-test',
        'name': 'Visibility test',
        'visibilityRules': [
          {
            'target': 'building.section.$section',
            'conditions': const [
              {
                'source': 'answer',
                'key': 'building.costIsExact',
                'operator': 'equals',
                'value': true,
              }
            ],
          }
        ],
      });
      const requirements = FieldRequirements({
        'building.buildingName': false,
        'building.ra9514Type': false,
        'building.storeys': false,
        'building.material': false,
        'building.cost': false,
        'building.fireLoad': false,
        'building.cbmsId': true,
        'building.fireFightingFacilities': true,
      });
      final result = validateBuildingForm(
        empty(),
        1,
        requirements: requirements,
        definition: definition,
      );
      expect(result.fieldErrors, isNot(contains(hiddenField)));
      expect(result.fieldErrors.length, 1);
      expect(
        validateBuildingForm(
          empty(),
          0,
          requirements: requirements,
          definition: definition,
        ).fieldErrors,
        contains('photo'),
      );
    });
  }
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

  test('photo remains required when a legacy sidecar marks it optional', () {
    final requirements = parseFieldRequirements('building.photo = optional');
    final result = validateBuildingForm(
      empty().copyWith(doesNotExist: true),
      0,
      requirements: requirements,
    );

    expect(result.fieldErrors, containsPair('photo', 'photo_required'));
    expect(result.isComplete, isFalse);
  });
}
