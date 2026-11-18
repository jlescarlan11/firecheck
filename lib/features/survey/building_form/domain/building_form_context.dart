import 'package:firecheck/core/forms/form_definition.dart';
import 'package:firecheck/core/forms/geometry_signal.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_state.dart';

FormEvaluationContext buildingFormContext(
  BuildingFormState state,
  GeometrySignal geometry,
) =>
    FormEvaluationContext(
      geometry: geometry,
      answers: {
        'building.doesNotExist': state.doesNotExist,
        'building.cbmsId': state.cbmsId,
        'building.buildingName': state.buildingName,
        'building.ra9514Type': state.ra9514Type,
        'building.storeys': state.storeys,
        'building.material': state.material,
        'building.costIsExact': state.costIsExact,
        'building.costAmount': state.costAmount,
        'building.costEstimateRange': state.costEstimateRange,
        'building.fireFightingFacilities': state.fireFightingFacilities,
        'building.fireLoad': state.fireLoad,
      },
    );

/// Uses the same section target and answer context as the rendered building form.
bool isBuildingSectionVisible(
  FormDefinition definition,
  BuildingFormState state,
  GeometrySignal geometry,
  String section,
) =>
    definition.isVisible(
      'building.section.$section',
      buildingFormContext(state, geometry),
    );
