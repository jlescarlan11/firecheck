import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/survey/olp_survey/domain/construction_details.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_form_state.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';

class HouseholdSurveyRepository {
  HouseholdSurveyRepository(this._db);
  final AppDatabase _db;

  Future<void> upsertForSubmission({
    required OlpFormState state,
    required String lebelNgKahinaan,
    required List<String> safetySuggestionKeys,
  }) async {
    final byCheckedSection = _packCheckedBySection(state.checkedCodes);
    await _db.into(_db.householdSurveys).insertOnConflictUpdate(
          HouseholdSurveysCompanion.insert(
            submissionId: state.submissionId,
            constructionDetailsJson:
                Value(jsonEncode(_encodeConstruction(state.constructionDetails))),
            kaayusanJson: Value(jsonEncode(byCheckedSection[OlpSection.b] ?? {})),
            koneksyongElektrikalJson:
                Value(jsonEncode(byCheckedSection[OlpSection.c] ?? {})),
            kusinaJson: Value(jsonEncode(byCheckedSection[OlpSection.d] ?? {})),
            daananOLabasanJson:
                Value(jsonEncode(byCheckedSection[OlpSection.e] ?? {})),
            lebelNgKahinaan: Value(lebelNgKahinaan),
            safetySuggestions: Value(jsonEncode(safetySuggestionKeys)),
            homeownerAcknowledged: Value(state.homeownerAcknowledged),
            completedAt: Value(state.completedAt),
          ),
        );
  }

  Future<OlpFormState?> loadForSubmission(String submissionId) async {
    final row = await (_db.select(_db.householdSurveys)
          ..where((t) => t.submissionId.equals(submissionId)))
        .getSingleOrNull();
    if (row == null) return null;
    final checked = <String>{
      ...decodeCheckedCodes(row.kaayusanJson),
      ...decodeCheckedCodes(row.koneksyongElektrikalJson),
      ...decodeCheckedCodes(row.kusinaJson),
      ...decodeCheckedCodes(row.daananOLabasanJson),
    };
    return OlpFormState(
      submissionId: submissionId,
      checkedCodes: checked,
      constructionDetails: decodeConstructionDetails(row.constructionDetailsJson),
      homeownerAcknowledged: row.homeownerAcknowledged,
      completedAt: row.completedAt,
    );
  }

  Map<OlpSection, Map<String, bool>> _packCheckedBySection(
    Set<String> checkedCodes,
  ) {
    final out = <OlpSection, Map<String, bool>>{
      for (final s in OlpSection.values) s: <String, bool>{},
    };
    for (final item in OlpRubric.items) {
      if (checkedCodes.contains(item.code)) {
        out[item.section]![item.code] = true;
      }
    }
    return out;
  }

  Map<String, Map<String, dynamic>> _encodeConstruction(
    Map<String, ConstructionDetail> details,
  ) {
    return details.map((element, detail) {
      final m = <String, dynamic>{'material': detail.material};
      if (detail.materialOther != null) {
        m['materialOther'] = detail.materialOther;
      }
      return MapEntry(element, m);
    });
  }

  static Set<String> decodeCheckedCodes(String json) {
    try {
      final parsed = jsonDecode(json);
      if (parsed is! Map) return const {};
      return parsed.entries
          .where((e) => e.value == true)
          .map((e) => e.key.toString())
          .toSet();
    } on Object {
      return const {};
    }
  }

  static Map<String, ConstructionDetail> decodeConstructionDetails(
    String json,
  ) {
    try {
      final parsed = jsonDecode(json);
      if (parsed is! Map) return const {};
      final out = <String, ConstructionDetail>{};
      parsed.forEach((key, value) {
        if (value is Map && value['material'] is String) {
          out[key.toString()] = ConstructionDetail(
            material: value['material'] as String,
            materialOther: value['materialOther'] as String?,
          );
        }
      });
      return out;
    } on Object {
      return const {};
    }
  }
}
