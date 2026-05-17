import 'package:firecheck/core/forms/field_requirements.dart';
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

ValidationResult validateRoadForm(
  RoadFormState state,
  int photoCount, {
  FieldRequirements requirements = FieldRequirements.allRequired,
}) {
  final errors = <String, String>{};
  final warnings = <String>[];

  if (requirements.isRequired(FieldRequirementKeys.roadPhoto) &&
      photoCount < 1) {
    errors['photo'] = 'photo_required';
  }

  if (state.doesNotExist) {
    return ValidationResult(fieldErrors: errors, warnings: warnings);
  }

  final widthRequired =
      requirements.isRequired(FieldRequirementKeys.roadWidthMeters);
  if (state.widthMeters == null) {
    if (widthRequired) errors['widthMeters'] = 'width_required_positive';
  } else if (state.widthMeters! <= 0) {
    // Out-of-range is still an error even if the field is "optional".
    errors['widthMeters'] = 'width_required_positive';
  } else if (state.widthMeters! > 30) {
    warnings.add('width_meters_warning_too_wide');
  }

  if (state.roadFeatures.contains('others') &&
      requirements.isRequired(FieldRequirementKeys.roadOthersDescription)) {
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
