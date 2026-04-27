import 'package:firecheck/features/survey/olp_survey/domain/olp_classification.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_form_state.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';

class OlpScoreResult {
  const OlpScoreResult({
    required this.totalScore,
    required this.sectionScores,
    required this.classification,
    required this.uncheckedItems,
  });
  final int totalScore;
  final Map<OlpSection, int> sectionScores;
  final OlpClassification classification;
  final List<OlpRubricItem> uncheckedItems;
}

OlpScoreResult computeOlpScore(OlpFormState state) {
  final checked = state.checkedCodes;
  final sectionScores = <OlpSection, int>{
    for (final s in OlpSection.values) s: 0,
  };
  var total = 0;
  final unchecked = <OlpRubricItem>[];
  for (final item in OlpRubric.items) {
    if (checked.contains(item.code)) {
      total++;
      sectionScores[item.section] = sectionScores[item.section]! + 1;
    } else {
      unchecked.add(item);
    }
  }
  return OlpScoreResult(
    totalScore: total,
    sectionScores: sectionScores,
    classification: classify(total),
    uncheckedItems: unchecked,
  );
}

OlpClassification classify(int score) {
  if (score >= OlpRubric.ligtasThreshold) return const Ligtas();
  if (score >= OlpRubric.mayroongThreshold) return const MayroongDapatIpangamba();
  return const LabisNaMapanganib();
}
