// Centralized model of which building-form fields are applicable to the
// current path through the form, and which of those still need an answer.
// Drives field-level visibility, automatic clearing of skipped answers,
// and the remaining-questions indicator.
//
// [geometry] flows through every applicability call so skip-logic that
// depends on the feature's shape — area thresholds, vertex counts — can
// re-evaluate the moment a reshape commits. Current rules don't consume
// the signal yet; the parameter exists so adding a geometry-dependent
// rule is a one-line change.
import 'package:firecheck/core/forms/field_requirements.dart';
import 'package:firecheck/core/forms/form_definition.dart';
import 'package:firecheck/core/forms/geometry_signal.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_context.dart';
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

/// Fields hidden by either the variant or the rendered definition sections.
/// This only controls applicability; it never clears saved answers.
Set<BuildingFormField> effectiveHiddenBuildingFields(
  BuildingFormState state, {
  Set<BuildingFormField> hidden = const {},
  FormDefinition definition = FormDefinition.legacy,
  GeometrySignal? geometry,
}) =>
    {
      ...hidden,
      for (final entry in _sectionFields.entries)
        if (!isBuildingSectionVisible(
          definition,
          state,
          geometry ?? GeometrySignal.empty,
          entry.key,
        ))
          ...entry.value,
    };

const _sectionFields = {
  'identity': {
    BuildingFormField.cbmsId,
    BuildingFormField.buildingName,
    BuildingFormField.ra9514Type,
  },
  'construction': {BuildingFormField.storeys, BuildingFormField.material},
  'cost': {BuildingFormField.costAmount, BuildingFormField.costEstimateRange},
  'fireFightingFacilities': {BuildingFormField.fireFightingFacilities},
  'fireLoad': {BuildingFormField.fireLoad},
};

/// True when the field should be visible AND collected for the current
/// state. [applyApplicability] clears the inactive cost alternative and
/// does-not-exist answers; visibility alone preserves existing saved values.
///
/// [hidden] is the form variant's `hideBuildingFields` set. When the
/// variant hides a field it is treated identically to a non-applicable
/// field: the input is not rendered and the remaining-questions chip skips
/// it. Existing hidden values are retained.
bool isApplicable(
  BuildingFormState s,
  BuildingFormField f, {
  Set<BuildingFormField> hidden = const {},
  GeometrySignal? geometry,
}) {
  if (hidden.contains(f)) return false;
  // `geometry` is intentionally unused by today's rules — see file header.
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
      return (s.cbmsId ?? '').trim().isNotEmpty;
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

int remainingQuestionCount(
  BuildingFormState s, {
  Set<BuildingFormField> hidden = const {},
  GeometrySignal? geometry,
  FieldRequirements? requirements,
  FormDefinition definition = FormDefinition.legacy,
}) {
  final effectiveHidden = effectiveHiddenBuildingFields(
    s,
    hidden: hidden,
    definition: definition,
    geometry: geometry,
  );
  var n = 0;
  for (final f in BuildingFormField.values) {
    if (!isApplicable(s, f, hidden: effectiveHidden, geometry: geometry)) {
      continue;
    }
    if (isAnswered(s, f)) continue;
    if (!(requirements ?? FieldRequirements.allRequired)
        .isRequired(buildingRequirementKeyFor(f))) {
      continue;
    }
    n++;
  }
  return n;
}

/// Shared sidecar key mapping for labels, counts and completion validation.
String buildingRequirementKeyFor(BuildingFormField f) {
  switch (f) {
    case BuildingFormField.buildingName:
      return FieldRequirementKeys.buildingName;
    case BuildingFormField.ra9514Type:
      return FieldRequirementKeys.buildingRa9514Type;
    case BuildingFormField.storeys:
      return FieldRequirementKeys.buildingStoreys;
    case BuildingFormField.material:
      return FieldRequirementKeys.buildingMaterial;
    case BuildingFormField.costAmount:
    case BuildingFormField.costEstimateRange:
      return FieldRequirementKeys.buildingCost;
    case BuildingFormField.fireLoad:
      return FieldRequirementKeys.buildingFireLoad;
    case BuildingFormField.cbmsId:
      return FieldRequirementKeys.buildingCbmsId;
    case BuildingFormField.fireFightingFacilities:
      return FieldRequirementKeys.buildingFireFightingFacilities;
  }
}

/// Clears answers for the does-not-exist path and the inactive cost input.
/// Variant- and definition-hidden answers remain saved; callers exclude them
/// from visibility, remaining counts and completion validation.
BuildingFormState applyApplicability(
  BuildingFormState s, {
  Set<BuildingFormField> hidden = const {},
  GeometrySignal? geometry,
}) {
  // `geometry` routed through for future skip-rules (Issue #44).
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
  // Visibility changes preserve saved answers, including hidden strings/lists.
  return s;
}

bool _nonEmpty(String? v) => v != null && v.isNotEmpty;
