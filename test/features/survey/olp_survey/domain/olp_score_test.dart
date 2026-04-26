import 'package:firecheck/features/survey/olp_survey/domain/olp_classification.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_form_state.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_score.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classify', () {
    test('score 0 → LabisNaMapanganib', () {
      expect(classify(0), isA<LabisNaMapanganib>());
    });
    test('score 11 → LabisNaMapanganib', () {
      expect(classify(11), isA<LabisNaMapanganib>());
    });
    test('score 12 → MayroongDapatIpangamba', () {
      expect(classify(12), isA<MayroongDapatIpangamba>());
    });
    test('score 23 → MayroongDapatIpangamba', () {
      expect(classify(23), isA<MayroongDapatIpangamba>());
    });
    test('score 24 → Ligtas', () {
      expect(classify(24), isA<Ligtas>());
    });
    test('score 35 → Ligtas', () {
      expect(classify(35), isA<Ligtas>());
    });
  });

  group('computeOlpScore', () {
    test('empty state → score 0, all 35 unchecked, LabisNaMapanganib', () {
      const state = OlpFormState(submissionId: 's1');
      final r = computeOlpScore(state);
      expect(r.totalScore, 0);
      expect(r.uncheckedItems.length, 35);
      expect(r.classification, isA<LabisNaMapanganib>());
      expect(r.sectionScores[OlpSection.b], 0);
      expect(r.sectionScores[OlpSection.c], 0);
      expect(r.sectionScores[OlpSection.d], 0);
      expect(r.sectionScores[OlpSection.e], 0);
    });

    test('all 35 checked → score 35, no unchecked, Ligtas', () {
      final allCodes = OlpRubric.items.map((i) => i.code).toSet();
      final state = OlpFormState(submissionId: 's1', checkedCodes: allCodes);
      final r = computeOlpScore(state);
      expect(r.totalScore, 35);
      expect(r.uncheckedItems, isEmpty);
      expect(r.classification, isA<Ligtas>());
      expect(r.sectionScores[OlpSection.b], 15);
      expect(r.sectionScores[OlpSection.c], 9);
      expect(r.sectionScores[OlpSection.d], 5);
      expect(r.sectionScores[OlpSection.e], 6);
    });

    test('partial checked → known per-section breakdown', () {
      const state = OlpFormState(
        submissionId: 's1',
        checkedCodes: {'B-01', 'B-02', 'C-10', 'D-25', 'E-30'},
      );
      final r = computeOlpScore(state);
      expect(r.totalScore, 5);
      expect(r.sectionScores[OlpSection.b], 2);
      expect(r.sectionScores[OlpSection.c], 1);
      expect(r.sectionScores[OlpSection.d], 1);
      expect(r.sectionScores[OlpSection.e], 1);
      expect(r.classification, isA<LabisNaMapanganib>());
      expect(r.uncheckedItems.length, 30);
    });

    test('unknown codes in checkedCodes are silently ignored', () {
      const state = OlpFormState(
        submissionId: 's1',
        checkedCodes: {'B-01', 'NOT-A-CODE', 'C-10'},
      );
      final r = computeOlpScore(state);
      expect(r.totalScore, 2);
    });
  });
}
