import 'package:firecheck/features/survey/road_form/domain/road_form_state.dart';

class ValidationResult {
  ValidationResult({
    required this.fieldErrors,
    required this.warnings,
  });
  final Map<String, String> fieldErrors;
  final List<String> warnings;

  bool get isComplete => fieldErrors.isEmpty;
}

ValidationResult validateRoadForm(RoadFormState state, int photoCount) {
  final errors = <String, String>{};
  final warnings = <String>[];

  // Photo always required (parity with building form).
  if (photoCount < 1) {
    errors['photo'] = 'photo_required';
  }

  if (state.doesNotExist) {
    return ValidationResult(fieldErrors: errors, warnings: warnings);
  }

  if (state.widthMeters == null || state.widthMeters! <= 0) {
    errors['widthMeters'] = 'width_required_positive';
  } else if (state.widthMeters! > 30) {
    warnings.add('width_meters_warning_too_wide');
  }

  if (state.roadFeatures.contains('others')) {
    final desc = state.othersDescription?.trim() ?? '';
    if (desc.isEmpty) {
      errors['othersDescription'] = 'others_description_required';
    }
  }

  if ((state.roadName ?? '').trim().isEmpty) {
    warnings.add('road_name_warning_empty');
  }

  return ValidationResult(fieldErrors: errors, warnings: warnings);
}
