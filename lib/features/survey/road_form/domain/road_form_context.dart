import 'package:firecheck/core/forms/form_definition.dart';
import 'package:firecheck/core/forms/geometry_signal.dart';
import 'package:firecheck/features/survey/road_form/domain/road_form_state.dart';

FormEvaluationContext roadFormContext(
  RoadFormState state,
  GeometrySignal geometry,
) =>
    FormEvaluationContext(
      geometry: geometry,
      answers: {
        'road.doesNotExist': state.doesNotExist,
        'road.isBridge': state.isBridge,
        'road.roadName': state.roadName,
        'road.widthMeters': state.widthMeters,
        'road.roadFeatures': state.roadFeatures,
        'road.othersDescription': state.othersDescription,
      },
    );
