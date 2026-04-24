class BuildingFormState {
  const BuildingFormState({
    required this.submissionId,
    this.cbmsId,
    this.buildingName,
    this.ra9514Type,
    this.storeys,
    this.material,
    this.costIsExact = false,
    this.costAmount,
    this.costEstimateRange,
    this.fireFightingFacilities = const [],
    this.fireLoad = const [],
    this.doesNotExist = false,
    this.overrideReason,
  });

  final String submissionId;
  final String? cbmsId;
  final String? buildingName;
  final String? ra9514Type;
  final int? storeys;
  final String? material;
  final bool costIsExact;
  final double? costAmount;
  final String? costEstimateRange;
  final List<String> fireFightingFacilities;
  final List<String> fireLoad;
  final bool doesNotExist;
  final String? overrideReason;

  BuildingFormState copyWith({
    String? cbmsId,
    String? buildingName,
    String? ra9514Type,
    int? storeys,
    String? material,
    bool? costIsExact,
    double? costAmount,
    String? costEstimateRange,
    List<String>? fireFightingFacilities,
    List<String>? fireLoad,
    bool? doesNotExist,
    String? overrideReason,
    bool clearCostAmount = false,
    bool clearCostEstimateRange = false,
  }) {
    return BuildingFormState(
      submissionId: submissionId,
      cbmsId: cbmsId ?? this.cbmsId,
      buildingName: buildingName ?? this.buildingName,
      ra9514Type: ra9514Type ?? this.ra9514Type,
      storeys: storeys ?? this.storeys,
      material: material ?? this.material,
      costIsExact: costIsExact ?? this.costIsExact,
      costAmount: clearCostAmount ? null : (costAmount ?? this.costAmount),
      costEstimateRange: clearCostEstimateRange
          ? null
          : (costEstimateRange ?? this.costEstimateRange),
      fireFightingFacilities:
          fireFightingFacilities ?? this.fireFightingFacilities,
      fireLoad: fireLoad ?? this.fireLoad,
      doesNotExist: doesNotExist ?? this.doesNotExist,
      overrideReason: overrideReason ?? this.overrideReason,
    );
  }
}
