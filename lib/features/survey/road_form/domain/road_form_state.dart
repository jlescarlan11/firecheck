class RoadFormState {
  const RoadFormState({
    required this.submissionId,
    this.isBridge = false,
    this.roadName,
    this.widthMeters,
    this.roadFeatures = const [],
    this.othersDescription,
    this.doesNotExist = false,
  });

  final String submissionId;
  final bool isBridge;
  final String? roadName;
  final double? widthMeters;
  final List<String> roadFeatures;
  final String? othersDescription;
  final bool doesNotExist;

  RoadFormState copyWith({
    bool? isBridge,
    String? roadName,
    double? widthMeters,
    List<String>? roadFeatures,
    String? othersDescription,
    bool? doesNotExist,
    bool clearOthersDescription = false,
  }) {
    return RoadFormState(
      submissionId: submissionId,
      isBridge: isBridge ?? this.isBridge,
      roadName: roadName ?? this.roadName,
      widthMeters: widthMeters ?? this.widthMeters,
      roadFeatures: roadFeatures ?? this.roadFeatures,
      othersDescription:
          clearOthersDescription ? null : (othersDescription ?? this.othersDescription),
      doesNotExist: doesNotExist ?? this.doesNotExist,
    );
  }
}
