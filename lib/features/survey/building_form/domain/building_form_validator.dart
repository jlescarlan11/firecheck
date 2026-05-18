import 'package:firecheck/core/forms/field_requirements.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_state.dart';

class ValidationResult {
  const ValidationResult({
    this.fieldErrors = const {},
    this.warnings = const [],
  });
  final Map<String, String> fieldErrors;
  final List<String> warnings;
  bool get isComplete => fieldErrors.isEmpty;
}

ValidationResult validateBuildingForm(
  BuildingFormState state,
  int photoCount, {
  FieldRequirements requirements = FieldRequirements.allRequired,
}) {
  final fieldErrors = <String, String>{};
  final warnings = <String>[];

  if (requirements.isRequired(FieldRequirementKeys.buildingPhoto) &&
      photoCount < 1) {
    fieldErrors['photo'] = 'photo_required';
  }

  if (!state.doesNotExist) {
    if (requirements.isRequired(FieldRequirementKeys.buildingName) &&
        (state.buildingName ?? '').trim().isEmpty) {
      fieldErrors['buildingName'] = 'required';
    }
    if (requirements.isRequired(FieldRequirementKeys.buildingRa9514Type) &&
        state.ra9514Type == null) {
      fieldErrors['ra9514Type'] = 'required';
    }
    final storeysRequired =
        requirements.isRequired(FieldRequirementKeys.buildingStoreys);
    if (state.storeys == null) {
      if (storeysRequired) fieldErrors['storeys'] = 'required';
    } else if (state.storeys! < 1) {
      // Even when optional, an out-of-range value is still an error: the
      // optional toggle controls "must answer", not "may submit garbage".
      fieldErrors['storeys'] = 'required';
    } else if (state.storeys! > 50) {
      warnings.add('storeys_warning_too_tall');
    }
    if (requirements.isRequired(FieldRequirementKeys.buildingMaterial) &&
        state.material == null) {
      fieldErrors['material'] = 'required';
    }
    if (requirements.isRequired(FieldRequirementKeys.buildingCost)) {
      final costExactOk = state.costIsExact &&
          state.costAmount != null &&
          state.costAmount! > 0;
      final costRangeOk = !state.costIsExact &&
          (state.costEstimateRange ?? '').isNotEmpty;
      if (!costExactOk && !costRangeOk) {
        fieldErrors['cost'] = 'required';
      }
    }
    if (requirements.isRequired(FieldRequirementKeys.buildingFireLoad) &&
        state.fireLoad.isEmpty) {
      fieldErrors['fireLoad'] = 'required';
    }
  }

  return ValidationResult(fieldErrors: fieldErrors, warnings: warnings);
}
