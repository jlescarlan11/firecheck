// lib/features/survey/road_form/domain/road_form_applicability.dart
//
// Same shape as the building variant: centralized applicability rules for
// road-form fields, driving US-6 / US-7 / US-8.
import 'package:firecheck/features/survey/road_form/domain/road_form_state.dart';

enum RoadFormField {
  roadName,
  widthMeters,
  roadFeatures,
  othersDescription,
}

bool isApplicable(RoadFormState s, RoadFormField f) {
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

int remainingQuestionCount(RoadFormState s) {
  var n = 0;
  for (final f in RoadFormField.values) {
    if (!isApplicable(s, f)) continue;
    if (isAnswered(s, f)) continue;
    n++;
  }
  return n;
}

RoadFormState applyApplicability(RoadFormState s) {
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
