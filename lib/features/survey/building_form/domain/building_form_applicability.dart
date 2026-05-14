// lib/features/survey/building_form/domain/building_form_applicability.dart
//
// Centralized model of which building-form fields are applicable to the
// current path through the form, and which of those still need an answer.
// Drives field-level visibility (US-6), automatic clearing of skipped
// answers (US-7) and the remaining-questions indicator (US-8).
import 'package:firecheck/features/survey/building_form/domain/building_form_state.dart';

enum BuildingFormField {
  cbmsId,
  buildingName,
  ra9514Type,
  storeys,
  material,
  costAmount,
  costEstimateRange,
  fireFightingFacilities,
  fireLoad,
}

/// True when the field should be visible AND collected for the current
/// state. Fields that are not applicable have their stored value cleared
/// by [applyApplicability] so a stale answer cannot survive a path change.
bool isApplicable(BuildingFormState s, BuildingFormField f) {
  // "Does not exist" short-circuits the whole survey: nothing else applies.
  if (s.doesNotExist) return false;
  switch (f) {
    case BuildingFormField.costAmount:
      return s.costIsExact;
    case BuildingFormField.costEstimateRange:
      return !s.costIsExact;
    case BuildingFormField.cbmsId:
    case BuildingFormField.buildingName:
    case BuildingFormField.ra9514Type:
    case BuildingFormField.storeys:
    case BuildingFormField.material:
    case BuildingFormField.fireFightingFacilities:
    case BuildingFormField.fireLoad:
      return true;
  }
}

bool isAnswered(BuildingFormState s, BuildingFormField f) {
  switch (f) {
    case BuildingFormField.cbmsId:
      return _nonEmpty(s.cbmsId);
    case BuildingFormField.buildingName:
      return _nonEmpty(s.buildingName);
    case BuildingFormField.ra9514Type:
      return _nonEmpty(s.ra9514Type);
    case BuildingFormField.storeys:
      return s.storeys != null;
    case BuildingFormField.material:
      return _nonEmpty(s.material);
    case BuildingFormField.costAmount:
      return s.costAmount != null;
    case BuildingFormField.costEstimateRange:
      return _nonEmpty(s.costEstimateRange);
    case BuildingFormField.fireFightingFacilities:
      return s.fireFightingFacilities.isNotEmpty;
    case BuildingFormField.fireLoad:
      return s.fireLoad.isNotEmpty;
  }
}

int remainingQuestionCount(BuildingFormState s) {
  var n = 0;
  for (final f in BuildingFormField.values) {
    if (!isApplicable(s, f)) continue;
    if (isAnswered(s, f)) continue;
    n++;
  }
  return n;
}

/// Returns a new state with any non-applicable field cleared. The notifier
/// runs this after every mutation so a previously-answered field can never
/// outlive the path it belonged to.
BuildingFormState applyApplicability(BuildingFormState s) {
  if (s.doesNotExist) {
    // Whole-form skip: clear every conditional answer, keep only the
    // submission id, the toggle itself, and the override reason (the latter
    // is associated with the path-skip decision, not with the cleared
    // answers).
    return BuildingFormState(
      submissionId: s.submissionId,
      doesNotExist: true,
      overrideReason: s.overrideReason,
    );
  }
  // The cost-input pair is mutually exclusive; clear whichever isn't active.
  if (s.costIsExact && s.costEstimateRange != null) {
    return s.copyWith(clearCostEstimateRange: true);
  }
  if (!s.costIsExact && s.costAmount != null) {
    return s.copyWith(clearCostAmount: true);
  }
  return s;
}

bool _nonEmpty(String? v) => v != null && v.isNotEmpty;
