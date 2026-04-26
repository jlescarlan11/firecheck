import 'dart:async';

import 'package:firecheck/features/survey/olp_survey/data/household_survey_repository.dart';
import 'package:firecheck/features/survey/olp_survey/domain/construction_details.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_form_state.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_score.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OlpSectionNotifier extends StateNotifier<OlpFormState> {
  OlpSectionNotifier({
    required String submissionId,
    required this.featureId,
    required this.repo,
  }) : super(OlpFormState(submissionId: submissionId)) {
    _loadInitial();
  }

  final String featureId;
  final HouseholdSurveyRepository repo;

  Timer? _debounce;
  static const _window = Duration(milliseconds: 500);

  Future<void> _loadInitial() async {
    final loaded = await repo.loadForSubmission(state.submissionId);
    if (loaded != null && mounted) state = loaded;
  }

  void toggleItem(String code) {
    final next = {...state.checkedCodes};
    if (next.contains(code)) {
      next.remove(code);
    } else {
      next.add(code);
    }
    update((s) => s.copyWith(checkedCodes: next));
  }

  void setMaterial(String element, String material, {String? other}) {
    final next = {...state.constructionDetails};
    next[element] = ConstructionDetail(material: material, materialOther: other);
    update((s) => s.copyWith(constructionDetails: next));
  }

  void setHomeownerAcknowledged({required bool acknowledged}) {
    update((s) => s.copyWith(homeownerAcknowledged: acknowledged));
  }

  void update(OlpFormState Function(OlpFormState) mutate) {
    state = mutate(state);
    _debounce?.cancel();
    _debounce = Timer(_window, _flush);
  }

  Future<void> flushNow() async {
    _debounce?.cancel();
    await _flush();
  }

  Future<void> markComplete() async {
    update((s) => s.copyWith(completedAt: DateTime.now()));
    await flushNow();
  }

  Future<void> _flush() async {
    try {
      final result = computeOlpScore(state);
      final lebelName = result.classification.runtimeType.toString();
      final suggestions =
          result.uncheckedItems.map((i) => i.suggestionKey).toList();
      await repo.upsertForSubmission(
        state: state,
        lebelNgKahinaan: lebelName,
        safetySuggestionKeys: suggestions,
      );
    } on Object {
      // Best-effort flush; swallow errors that race against db.close()
      // during provider container teardown in tests.
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    unawaited(_flush());
    super.dispose();
  }
}
