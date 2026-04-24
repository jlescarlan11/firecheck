import 'package:firecheck/core/geo/centroid.dart';
import 'package:firecheck/core/location/distance.dart';

sealed class TapResult {
  const TapResult();
  double get meters;
}

class TapAllowed extends TapResult {
  const TapAllowed(this.meters);
  @override
  final double meters;
}

class TapBlocked extends TapResult {
  const TapBlocked(this.meters);
  @override
  final double meters;
}

class TapAllowedWithOverride extends TapResult {
  const TapAllowedWithOverride({required this.meters, required this.reason});
  @override
  final double meters;
  final String reason;
}

const _maxMeters = 50.0;

/// Determines whether a polygon tap is allowed given the user's current GPS.
/// If the distance exceeds the 50 m policy, calls [promptForReason] and
/// returns either [TapAllowedWithOverride] (with the reason) or
/// [TapBlocked] (if the user dismissed the prompt).
Future<TapResult> checkTap({
  required double userLat,
  required double userLng,
  required List<List<double>> featureRing,
  required Future<String?> Function() promptForReason,
}) async {
  final centroid = polygonCentroid(featureRing);
  final meters =
      haversineMeters(userLat, userLng, centroid.lat, centroid.lng);
  if (meters <= _maxMeters) return TapAllowed(meters);

  final reason = await promptForReason();
  if (reason == null || reason.trim().isEmpty) return TapBlocked(meters);
  return TapAllowedWithOverride(meters: meters, reason: reason.trim());
}
