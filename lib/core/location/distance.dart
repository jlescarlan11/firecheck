import 'dart:math' as math;

/// Great-circle distance in meters between two WGS84 points, using the
/// haversine formula. Accurate to ~0.5% for distances up to a few thousand
/// kilometers.
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusMeters = 6371000.0;

  final dLat = _toRadians(lat2 - lat1);
  final dLng = _toRadians(lng2 - lng1);
  final rLat1 = _toRadians(lat1);
  final rLat2 = _toRadians(lat2);

  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.sin(dLng / 2) *
          math.sin(dLng / 2) *
          math.cos(rLat1) *
          math.cos(rLat2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

  return earthRadiusMeters * c;
}

double _toRadians(double degrees) => degrees * math.pi / 180;
