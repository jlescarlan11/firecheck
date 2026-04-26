import 'package:firecheck/features/survey/olp_survey/domain/construction_details.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_form_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default state has empty maps + acknowledged=false + no completedAt', () {
    const s = OlpFormState(submissionId: 's1');
    expect(s.checkedCodes, isEmpty);
    expect(s.constructionDetails, isEmpty);
    expect(s.homeownerAcknowledged, isFalse);
    expect(s.completedAt, isNull);
  });

  test('copyWith updates only the named fields', () {
    const s = OlpFormState(submissionId: 's1');
    final s2 = s.copyWith(homeownerAcknowledged: true);
    expect(s2.homeownerAcknowledged, isTrue);
    expect(s2.checkedCodes, isEmpty);
    expect(s2.submissionId, 's1');
  });

  test('checkedCodes replaces wholesale', () {
    const s = OlpFormState(submissionId: 's1', checkedCodes: {'B-01'});
    final s2 = s.copyWith(checkedCodes: {'C-10', 'C-11'});
    expect(s2.checkedCodes, {'C-10', 'C-11'});
  });

  test('clearCompletedAt resets the timestamp', () {
    final s = OlpFormState(submissionId: 's1', completedAt: DateTime(2026));
    final s2 = s.copyWith(clearCompletedAt: true);
    expect(s2.completedAt, isNull);
  });

  test('ConstructionDetail captures material + materialOther', () {
    const d = ConstructionDetail(material: 'others', materialOther: 'galvanized iron');
    expect(d.material, 'others');
    expect(d.materialOther, 'galvanized iron');
  });
}
