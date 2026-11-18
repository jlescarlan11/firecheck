import 'package:firecheck/core/forms/field_requirements.dart';
import 'package:firecheck/core/forms/form_definition.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_applicability.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_state.dart';
import 'package:flutter_test/flutter_test.dart';

BuildingFormState _empty() => const BuildingFormState(submissionId: 's1');

void main() {
  for (final section in ['identity', 'fireFightingFacilities']) {
    test('definition-hidden $section skips its required new answer', () {
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
      final state = _empty();
      expect(
        remainingQuestionCount(
          state,
          requirements: requirements,
          definition: definition,
        ),
        1,
      );
    });
  }
  test('new fields agree on explicit required, optional and hidden counts', () {
    final required = parseFieldRequirements(
      'building.cbmsId=required\nbuilding.fireFightingFacilities=required',
    );
    final optional = parseFieldRequirements(
      'building.cbmsId=optional\nbuilding.fireFightingFacilities=optional',
    );
    expect(remainingQuestionCount(_empty(), requirements: required), 8);
    expect(remainingQuestionCount(_empty(), requirements: optional), 6);
    expect(
      remainingQuestionCount(
        _empty(),
        requirements: required,
        hidden: {
          BuildingFormField.cbmsId,
          BuildingFormField.fireFightingFacilities,
        },
      ),
      6,
    );
    expect(
      remainingQuestionCount(
        _empty().copyWith(cbmsId: 'freeform', fireFightingFacilities: ['None']),
        requirements: required,
      ),
      6,
    );
    expect(
      remainingQuestionCount(
        _empty().copyWith(doesNotExist: true),
        requirements: required,
      ),
      0,
    );
  });

  group('US-6 isApplicable', () {
    test('costAmount only applies when costIsExact=true', () {
      expect(
        isApplicable(
          _empty().copyWith(costIsExact: true),
          BuildingFormField.costAmount,
        ),
        isTrue,
      );
      expect(
        isApplicable(
          _empty().copyWith(costIsExact: false),
          BuildingFormField.costAmount,
        ),
        isFalse,
      );
    });

    test('costEstimateRange only applies when costIsExact=false', () {
      expect(
        isApplicable(
          _empty().copyWith(costIsExact: false),
          BuildingFormField.costEstimateRange,
        ),
        isTrue,
      );
      expect(
        isApplicable(
          _empty().copyWith(costIsExact: true),
          BuildingFormField.costEstimateRange,
        ),
        isFalse,
      );
    });

    test('doesNotExist=true makes every conditional field inapplicable', () {
      final s = _empty().copyWith(doesNotExist: true);
      for (final f in BuildingFormField.values) {
        expect(isApplicable(s, f), isFalse, reason: '$f');
      }
    });

    test('US-41 variant-hidden unanswered field drops from the count', () {
      // Empty state: buildingName is applicable and unanswered, so it
      // contributes to the remaining-questions tally.
      final s = _empty();
      expect(isApplicable(s, BuildingFormField.buildingName), isTrue);
      const hidden = {BuildingFormField.buildingName};
      expect(
        isApplicable(s, BuildingFormField.buildingName, hidden: hidden),
        isFalse,
      );
      final before = remainingQuestionCount(s);
      final after = remainingQuestionCount(s, hidden: hidden);
      expect(
        after,
        before - 1,
        reason: 'hiding an unanswered applicable field reduces the count by 1',
      );
    });
  });

  group('US-7 applyApplicability clears skipped answers', () {
    test('switching costIsExact=true clears costEstimateRange', () {
      final dirty = _empty().copyWith(
        costIsExact: true,
        costEstimateRange: '100k-500k',
      );
      final swept = applyApplicability(dirty);
      expect(swept.costEstimateRange, isNull);
      expect(swept.costIsExact, isTrue);
    });

    test('switching costIsExact=false clears costAmount', () {
      final dirty = _empty().copyWith(costAmount: 1234567);
      final swept = applyApplicability(dirty);
      expect(swept.costAmount, isNull);
    });

    test('doesNotExist=true clears every captured answer', () {
      final dirty = _empty().copyWith(
        doesNotExist: true,
        buildingName: 'Hall',
        storeys: 5,
        costAmount: 99,
        fireFightingFacilities: ['sprinkler'],
        fireLoad: ['paper'],
      );
      final swept = applyApplicability(dirty);
      expect(swept.buildingName, isNull);
      expect(swept.storeys, isNull);
      expect(swept.costAmount, isNull);
      expect(swept.fireFightingFacilities, isEmpty);
      expect(swept.fireLoad, isEmpty);
      // The toggle itself is preserved.
      expect(swept.doesNotExist, isTrue);
    });
  });

  group('US-8 remainingQuestionCount', () {
    test(
        'empty form: all 6 legacy required fields unanswered (costEstimateRange branch)',
        () {
      // costIsExact defaults to false, so costEstimateRange is the active cost field.
      // Six required questions remain; omitted CBMS/facilities are optional.
      expect(remainingQuestionCount(_empty()), 6);
    });

    test('answering a field decrements the count', () {
      final s = _empty().copyWith(buildingName: 'Hall');
      expect(remainingQuestionCount(s), 5);
    });

    test('switching cost path does not double-count the other branch', () {
      final s = _empty().copyWith(costIsExact: true, costAmount: 100);
      // costEstimateRange is no longer applicable; costAmount is answered.
      expect(remainingQuestionCount(s), 5);
    });

    test('doesNotExist=true → zero remaining (whole form is skipped)', () {
      final s = _empty().copyWith(doesNotExist: true);
      expect(remainingQuestionCount(s), 0);
    });
  });
}
