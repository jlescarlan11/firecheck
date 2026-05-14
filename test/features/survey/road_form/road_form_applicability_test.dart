import 'package:firecheck/features/survey/road_form/domain/road_form_applicability.dart';
import 'package:firecheck/features/survey/road_form/domain/road_form_state.dart';
import 'package:flutter_test/flutter_test.dart';

RoadFormState _empty() => const RoadFormState(submissionId: 's1');

void main() {
  group('US-6 isApplicable', () {
    test('othersDescription only applies when roadFeatures contains "others"', () {
      expect(isApplicable(_empty(), RoadFormField.othersDescription), isFalse);
      final withOthers = _empty().copyWith(roadFeatures: ['others']);
      expect(isApplicable(withOthers, RoadFormField.othersDescription), isTrue);
    });

    test('doesNotExist=true makes everything inapplicable', () {
      final s = _empty().copyWith(doesNotExist: true);
      for (final f in RoadFormField.values) {
        expect(isApplicable(s, f), isFalse, reason: '$f');
      }
    });
  });

  group('US-7 applyApplicability clears skipped answers', () {
    test('removing "others" clears othersDescription', () {
      final dirty = _empty().copyWith(
        roadFeatures: ['pedestrian'],
        othersDescription: 'leftover note',
      );
      final swept = applyApplicability(dirty);
      expect(swept.othersDescription, isNull);
    });

    test('"others" still present → othersDescription survives', () {
      final s = _empty().copyWith(
        roadFeatures: ['others'],
        othersDescription: 'keep me',
      );
      final swept = applyApplicability(s);
      expect(swept.othersDescription, 'keep me');
    });

    test('doesNotExist=true clears all answers', () {
      final dirty = _empty().copyWith(
        doesNotExist: true,
        roadName: 'Main',
        widthMeters: 6,
        roadFeatures: ['others'],
        othersDescription: 'foo',
      );
      final swept = applyApplicability(dirty);
      expect(swept.roadName, isNull);
      expect(swept.widthMeters, isNull);
      expect(swept.roadFeatures, isEmpty);
      expect(swept.othersDescription, isNull);
      expect(swept.doesNotExist, isTrue);
    });
  });

  group('US-8 remainingQuestionCount', () {
    test('empty form: 3 applicable fields (others-description is hidden)', () {
      expect(remainingQuestionCount(_empty()), 3);
    });

    test('selecting "others" surfaces othersDescription as a new question', () {
      final s = _empty().copyWith(roadFeatures: ['others']);
      // roadFeatures now answered (-1) but othersDescription appears (+1) → still 3.
      expect(remainingQuestionCount(s), 3);
    });

    test('doesNotExist=true zeroes the count', () {
      expect(
        remainingQuestionCount(_empty().copyWith(doesNotExist: true)),
        0,
      );
    });
  });
}
