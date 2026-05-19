// Same shape as the building variant: centralized applicability rules for
// road-form fields, driving field visibility, auto-clearing of skipped
// answers, and the remaining-questions indicator.
//
// [geometry] is threaded through so geometry-dependent skip rules
// re-evaluate when a road polyline is reshaped mid-survey.
import 'package:firecheck/core/forms/field_requirements.dart';
import 'package:firecheck/core/forms/geometry_signal.dart';
import 'package:firecheck/features/survey/road_form/domain/road_form_state.dart';

enum RoadFormField {
  roadName,
  widthMeters,
  roadFeatures,
  othersDescription,
}

/// [hidden] is the form variant's `hideRoadFields` set. When the variant
/// hides a field, it is treated identically to a non-applicable field:
/// not rendered, not counted.
bool isApplicable(
  RoadFormState s,
  RoadFormField f, {
  Set<RoadFormField> hidden = const {},
  GeometrySignal? geometry,
}) {
  if (hidden.contains(f)) return false;
  // `geometry` is intentionally unused by today's rules — see file header.
  if (s.doesNotExist) return false;
  switch (f) {
    case RoadFormField.othersDescription:
      return s.roadFeatures.contains('others');
    case RoadFormField.roadName:
    case RoadFormField.widthMeters:
    case RoadFormField.roadFeatures:
      return true;
  }
}

bool isAnswered(RoadFormState s, RoadFormField f) {
  switch (f) {
    case RoadFormField.roadName:
      return _nonEmpty(s.roadName);
    case RoadFormField.widthMeters:
      return s.widthMeters != null;
    case RoadFormField.roadFeatures:
      return s.roadFeatures.isNotEmpty;
    case RoadFormField.othersDescription:
      return _nonEmpty(s.othersDescription);
  }
}

int remainingQuestionCount(
  RoadFormState s, {
  Set<RoadFormField> hidden = const {},
  GeometrySignal? geometry,
  FieldRequirements? requirements,
}) {
  var n = 0;
  for (final f in RoadFormField.values) {
    if (!isApplicable(s, f, hidden: hidden, geometry: geometry)) continue;
    if (isAnswered(s, f)) continue;
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

String? _requirementKeyFor(RoadFormField f) {
  switch (f) {
    case RoadFormField.widthMeters:
      return FieldRequirementKeys.roadWidthMeters;
    case RoadFormField.roadFeatures:
      return FieldRequirementKeys.roadFeatures;
    case RoadFormField.othersDescription:
      return FieldRequirementKeys.roadOthersDescription;
    case RoadFormField.roadName:
      return null;
  }
}

RoadFormState applyApplicability(
  RoadFormState s, {
  Set<RoadFormField> hidden = const {},
  GeometrySignal? geometry,
}) {
  // `geometry` routed through for future skip-rules (Issue #44).
  if (s.doesNotExist) {
    return RoadFormState(submissionId: s.submissionId, doesNotExist: true);
  }
  // "Others description" only applies when the "others" feature is selected.
  if (!s.roadFeatures.contains('others') && s.othersDescription != null) {
    return s.copyWith(clearOthersDescription: true);
  }
  return s;
}

bool _nonEmpty(String? v) => v != null && v.isNotEmpty;
