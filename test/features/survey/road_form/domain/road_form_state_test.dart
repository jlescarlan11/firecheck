import 'package:firecheck/features/survey/road_form/domain/road_form_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default state has no values set', () {
    const s = RoadFormState(submissionId: 's1');
    expect(s.isBridge, isFalse);
    expect(s.roadName, isNull);
    expect(s.widthMeters, isNull);
    expect(s.roadFeatures, isEmpty);
    expect(s.othersDescription, isNull);
    expect(s.doesNotExist, isFalse);
  });

  test('copyWith updates only the named fields', () {
    const s = RoadFormState(submissionId: 's1');
    final s2 = s.copyWith(roadName: 'Mango Ave', widthMeters: 4.5);
    expect(s2.roadName, 'Mango Ave');
    expect(s2.widthMeters, 4.5);
    expect(s2.isBridge, isFalse);
    expect(s2.submissionId, 's1');
  });

  test('clearOthersDescription removes the field', () {
    const s = RoadFormState(
      submissionId: 's1',
      othersDescription: 'street vendors',
    );
    final s2 = s.copyWith(clearOthersDescription: true);
    expect(s2.othersDescription, isNull);
  });

  test('roadFeatures replaces wholesale (no merge)', () {
    const s = RoadFormState(
      submissionId: 's1',
      roadFeatures: ['vendor', 'parking'],
    );
    final s2 = s.copyWith(roadFeatures: ['pedestrian']);
    expect(s2.roadFeatures, ['pedestrian']);
  });
}
