import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/olp_survey/data/household_survey_repository.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_form_state.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section_notifier.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final householdSurveyRepositoryProvider =
    Provider<HouseholdSurveyRepository>((ref) {
  return HouseholdSurveyRepository(ref.watch(appDatabaseProvider));
});

@immutable
class OlpFormKey {
  const OlpFormKey({required this.submissionId, required this.featureId});
  final String submissionId;
  final String featureId;

  @override
  bool operator ==(Object other) =>
      other is OlpFormKey &&
      other.submissionId == submissionId &&
      other.featureId == featureId;

  @override
  int get hashCode => Object.hash(submissionId, featureId);
}

final olpSectionNotifierProvider = StateNotifierProvider.autoDispose
    .family<OlpSectionNotifier, OlpFormState, OlpFormKey>((ref, key) {
  return OlpSectionNotifier(
    submissionId: key.submissionId,
    featureId: key.featureId,
    repo: ref.watch(householdSurveyRepositoryProvider),
  );
});
