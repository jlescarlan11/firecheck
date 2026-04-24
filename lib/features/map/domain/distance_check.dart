import 'package:firecheck/core/location/distance.dart';

sealed class DistanceCheckResult {
  const DistanceCheckResult();
  double get meters;
}

class DistanceCheckPass extends DistanceCheckResult {
  const DistanceCheckPass(this.meters);
  @override
  final double meters;
}

class DistanceCheckFail extends DistanceCheckResult {
  const DistanceCheckFail(this.meters);
  @override
  final double meters;
}

const _maxMeters = 50.0;

DistanceCheckResult distanceCheck({
  required double userLat,
  required double userLng,
  required double featureCentroidLat,
  required double featureCentroidLng,
}) {
  final meters = haversineMeters(
    userLat,
    userLng,
    featureCentroidLat,
    featureCentroidLng,
  );
  if (meters <= _maxMeters) {
    return DistanceCheckPass(meters);
  }
  return DistanceCheckFail(meters);
}
