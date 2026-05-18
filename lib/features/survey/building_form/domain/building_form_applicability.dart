// lib/features/survey/building_form/domain/building_form_applicability.dart
//
// Centralized model of which building-form fields are applicable to the
// current path through the form, and which of those still need an answer.
// Drives field-level visibility (US-6), automatic clearing of skipped
// answers (US-7) and the remaining-questions indicator (US-8).
//
// [geometry] flows through every applicability call so skip-logic that
// depends on the feature's shape — area thresholds, vertex counts — can
// re-evaluate the moment a reshape commits (Issue #44). Current rules
// don't consume the signal yet; the parameter exists so adding a
// geometry-dependent rule is a one-line change.
import 'package:firecheck/core/forms/field_requirements.dart';
import 'package:firecheck/core/forms/geometry_signal.dart';
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
///
/// [hidden] is the form variant's `hideBuildingFields` set (US-41). When
/// the variant hides a field it is treated identically to a non-applicable
/// field: the input is not rendered, the value is auto-cleared, and the
/// remaining-questions chip skips it.
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

int remainingQuestionCount(
  BuildingFormState s, {
  Set<BuildingFormField> hidden = const {},
  GeometrySignal? geometry,
  FieldRequirements? requirements,
}) {
  var n = 0;
  for (final f in BuildingFormField.values) {
    if (!isApplicable(s, f, hidden: hidden, geometry: geometry)) continue;
    if (isAnswered(s, f)) continue;
    // Optional fields don't count as "questions left" — the user can submit
    // without filling them in (Issue #43, sidecar-driven validation).
    final key = _requirementKeyFor(f);
    if (key != null &&
        requirements != null &&
        !requirements.isRequired(key)) {
      continue;
    }
    n++;
  }
  return n;
}

/// Maps each [BuildingFormField] to the requirement key the sidecar config
/// uses. Returns null for fields that don't have a corresponding key — they
/// always count as remaining when unanswered (today only [cbmsId] and
/// [fireFightingFacilities] fall in this bucket; both are pre-#43 optional
/// in spirit but not yet wired into the sidecar).
String? _requirementKeyFor(BuildingFormField f) {
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
    case BuildingFormField.fireFightingFacilities:
      return null;
  }
}

/// Returns a new state with any non-applicable field cleared. The notifier
/// runs this after every mutation so a previously-answered field can never
/// outlive the path it belonged to. Fields hidden by the active form
/// variant are also cleared — a hidden field is just an always-inapplicable
/// field from the user's perspective.
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
  // Note: variant-hidden String/list fields are NOT auto-cleared here.
  // BuildingFormState's copyWith uses the `value ?? this.value` pattern so
  // there's no path to null out a String field, and adding per-field clear
  // flags is out of scope for the variant-wiring fix. The hidden field is
  // simply never rendered and never counted, so the user can't enter a value
  // for it in the first place; a pre-existing value (from before the variant
  // hid it) survives untouched. If/when that becomes a problem, add explicit
  // clear flags to copyWith and call them here.
  return s;
}

bool _nonEmpty(String? v) => v != null && v.isNotEmpty;
