import 'package:firecheck/core/forms/field_requirements.dart';
import 'package:firecheck/features/survey/road_form/domain/road_form_state.dart';
import 'package:firecheck/features/survey/road_form/domain/road_form_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RoadFormState empty() => const RoadFormState(submissionId: 's1');

  group('validateRoadForm — does not exist OFF', () {
    test('empty form has photo + width blockers', () {
      final r = validateRoadForm(empty(), 0);
      expect(r.fieldErrors.keys, containsAll(['photo', 'widthMeters']));
      expect(r.isComplete, isFalse);
    });

    test('width=0 still blocks', () {
      final s = empty().copyWith(widthMeters: 0);
      final r = validateRoadForm(s, 1);
      expect(r.fieldErrors.keys, contains('widthMeters'));
    });

    test('width set + photo + no others-feature → complete', () {
      final s = empty().copyWith(widthMeters: 4.5);
      final r = validateRoadForm(s, 1);
      expect(r.fieldErrors, isEmpty);
      expect(r.isComplete, isTrue);
    });

    test('"others" feature requires othersDescription', () {
      final s = empty().copyWith(
        widthMeters: 4.5,
        roadFeatures: ['others'],
      );
      final r = validateRoadForm(s, 1);
      expect(r.fieldErrors.keys, contains('othersDescription'));
    });

    test('"others" feature with description satisfies blocker', () {
      final s = empty().copyWith(
        widthMeters: 4.5,
        roadFeatures: ['others'],
        othersDescription: 'goat crossing',
      );
      final r = validateRoadForm(s, 1);
      expect(r.fieldErrors, isEmpty);
    });

    test('width > 30m yields a warning, still complete', () {
      final s = empty().copyWith(widthMeters: 45);
      final r = validateRoadForm(s, 1);
      expect(r.warnings, contains('width_meters_warning_too_wide'));
      expect(r.isComplete, isTrue);
    });

    test('empty road name yields a warning, still complete', () {
      final s = empty().copyWith(widthMeters: 4.5);
      final r = validateRoadForm(s, 1);
      expect(r.warnings, contains('road_name_warning_empty'));
      expect(r.isComplete, isTrue);
    });
  });

  group('validateRoadForm — does not exist ON', () {
    test('only photo is required when doesNotExist=true', () {
      final s = empty().copyWith(doesNotExist: true);
      final r = validateRoadForm(s, 0);
      expect(r.fieldErrors.keys.toList(), ['photo']);
    });

    test('with photo → complete', () {
      final s = empty().copyWith(doesNotExist: true);
      final r = validateRoadForm(s, 1);
      expect(r.isComplete, isTrue);
    });
  });

  test('photo remains required when a legacy sidecar marks it optional', () {
    final requirements = parseFieldRequirements('road.photo = optional');
    final result = validateRoadForm(
      empty().copyWith(doesNotExist: true),
      0,
      requirements: requirements,
    );

    expect(result.fieldErrors, containsPair('photo', 'photo_required'));
    expect(result.isComplete, isFalse);
  });
}
