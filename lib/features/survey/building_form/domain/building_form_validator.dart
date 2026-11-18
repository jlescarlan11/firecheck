import 'package:firecheck/core/forms/field_requirements.dart';
import 'package:firecheck/core/forms/form_definition.dart';
import 'package:firecheck/core/forms/geometry_signal.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_applicability.dart';
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
  Set<BuildingFormField> hidden = const {},
  FormDefinition definition = FormDefinition.legacy,
  GeometrySignal? geometry,
}) {
  final effectiveHidden = effectiveHiddenBuildingFields(
    state,
    hidden: hidden,
    definition: definition,
    geometry: geometry,
  );
  final fieldErrors = <String, String>{};
  final warnings = <String>[];
  bool required(BuildingFormField field) =>
      isApplicable(state, field, hidden: effectiveHidden, geometry: geometry) &&
      requirements.isRequired(buildingRequirementKeyFor(field));

  // Photos are durable field evidence, not a configurable questionnaire
  // field. The photo strip always presents one photo as required, so the
  // completion contract must enforce the same invariant even when a legacy
  // field_requirements.txt marks building.photo optional.
  if (photoCount < 1) {
    fieldErrors['photo'] = 'photo_required';
  }

  if (!state.doesNotExist) {
    for (final field in [
      BuildingFormField.cbmsId,
      BuildingFormField.fireFightingFacilities,
    ]) {
      if (required(field) && !isAnswered(state, field)) {
        fieldErrors[field.name] = 'required';
      }
    }
    if (required(BuildingFormField.buildingName) &&
        (state.buildingName ?? '').trim().isEmpty) {
      fieldErrors['buildingName'] = 'required';
    }
    if (required(BuildingFormField.ra9514Type) && state.ra9514Type == null) {
      fieldErrors['ra9514Type'] = 'required';
    }
    final storeysRequired = required(BuildingFormField.storeys);
    if (isApplicable(
      state,
      BuildingFormField.storeys,
      hidden: effectiveHidden,
      geometry: geometry,
    )) {
      if (state.storeys == null) {
        if (storeysRequired) fieldErrors['storeys'] = 'required';
      } else if (state.storeys! < 1) {
        // Optional supplied values must still satisfy existing validity rules.
        fieldErrors['storeys'] = 'required';
      } else if (state.storeys! > 50) {
        warnings.add('storeys_warning_too_tall');
      }
    }
    if (required(BuildingFormField.material) && state.material == null) {
      fieldErrors['material'] = 'required';
    }
    if (required(
      state.costIsExact
          ? BuildingFormField.costAmount
          : BuildingFormField.costEstimateRange,
    )) {
      final costExactOk = state.costIsExact &&
          state.costAmount != null &&
          state.costAmount! > 0;
      final costRangeOk =
          !state.costIsExact && (state.costEstimateRange ?? '').isNotEmpty;
      if (!costExactOk && !costRangeOk) {
        fieldErrors['cost'] = 'required';
      }
    }
    if (required(BuildingFormField.fireLoad) && state.fireLoad.isEmpty) {
      fieldErrors['fireLoad'] = 'required';
    }
  }

  return ValidationResult(fieldErrors: fieldErrors, warnings: warnings);
}
