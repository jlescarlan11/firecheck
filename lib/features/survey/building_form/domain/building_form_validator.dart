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
  int photoCount,
) {
  final fieldErrors = <String, String>{};
  final warnings = <String>[];

  if (photoCount < 1) {
    fieldErrors['photo'] = 'photo_required';
  }

  if (!state.doesNotExist) {
    if ((state.buildingName ?? '').trim().isEmpty) {
      fieldErrors['buildingName'] = 'required';
    }
    if (state.ra9514Type == null) {
      fieldErrors['ra9514Type'] = 'required';
    }
    if (state.storeys == null || state.storeys! < 1) {
      fieldErrors['storeys'] = 'required';
    } else if (state.storeys! > 50) {
      warnings.add('storeys_warning_too_tall');
    }
    if (state.material == null) {
      fieldErrors['material'] = 'required';
    }
    final costExactOk = state.costIsExact &&
        state.costAmount != null &&
        state.costAmount! > 0;
    final costRangeOk = !state.costIsExact &&
        (state.costEstimateRange ?? '').isNotEmpty;
    if (!costExactOk && !costRangeOk) {
      fieldErrors['cost'] = 'required';
    }
    if (state.fireLoad.isEmpty) {
      fieldErrors['fireLoad'] = 'required';
    }
  }

  return ValidationResult(fieldErrors: fieldErrors, warnings: warnings);
}
