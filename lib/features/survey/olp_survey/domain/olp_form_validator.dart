import 'package:firecheck/features/survey/olp_survey/domain/olp_form_state.dart';

class OlpValidationResult {
  OlpValidationResult({
    required this.canMarkComplete,
    required this.fieldErrors,
  });
  final bool canMarkComplete;
  final Map<String, String> fieldErrors;
}

OlpValidationResult validateOlpForFinalize(OlpFormState state) {
  final errors = <String, String>{};
  if (!state.homeownerAcknowledged) {
    errors['homeownerAcknowledged'] = 'homeowner_must_agree';
  }
  // Section A incomplete is a warning, not a blocker (PRD §9).
  // Partial completion is allowed — unchecked items treated as 'false', not 'missing' (PRD §9).
  return OlpValidationResult(
    canMarkComplete: errors.isEmpty,
    fieldErrors: errors,
  );
}
