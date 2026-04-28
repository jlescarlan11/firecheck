import 'dart:convert';
import 'dart:math' as math;

class LatLng {
  const LatLng(this.lat, this.lng);
  final double lat;
  final double lng;
}

class PolygonBounds {
  const PolygonBounds({required this.center, required this.zoom});
  final LatLng center;
  final double zoom;
}

/// Computes a bounding-box centroid and a zoom-to-fit zoom level for a
/// GeoJSON Polygon. Returns null if the input is empty, malformed, or not
/// a Polygon. Zoom is clamped to [12, 18] — too far out fails to show
/// useful context, too far in over-magnifies tiny boundaries.
PolygonBounds? polygonBoundsFromGeojson(String geojson) {
  if (geojson.isEmpty) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(geojson);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  if (decoded['type'] != 'Polygon') return null;
  final coords = decoded['coordinates'];
  if (coords is! List<Object?>) return null;
  if (coords.isEmpty) return null;

  double minLat = double.infinity, maxLat = -double.infinity;
  double minLng = double.infinity, maxLng = -double.infinity;
  var pointCount = 0;

  for (final ring in coords) {
    if (ring is! List<Object?>) return null;
    for (final p in ring) {
      if (p is! List<Object?>) return null;
      if (p.length < 2) return null;
      final lng = p[0];
      final lat = p[1];
      if (lng is! num || lat is! num) return null;
      minLat = math.min(minLat, lat.toDouble());
      maxLat = math.max(maxLat, lat.toDouble());
      minLng = math.min(minLng, lng.toDouble());
      maxLng = math.max(maxLng, lng.toDouble());
      pointCount++;
    }
  }
  if (pointCount == 0) return null;

  final centerLat = (minLat + maxLat) / 2.0;
  final centerLng = (minLng + maxLng) / 2.0;

  // Bounding-box diagonal in meters (haversine on the diagonal corners).
  final diagonalM = _haversineMeters(minLat, minLng, maxLat, maxLng);

  // Mapbox/Web Mercator ground resolution at the equator at zoom z is
  // ~156543.03 / 2^z meters per pixel. Latitude scaling: multiply by cos(lat).
  // Pick zoom so the diagonal fits in ~512 pixels (a comfortable viewport).
  const targetPixels = 512.0;
  final cosLat = math.cos(centerLat * math.pi / 180.0).abs();
  // groundRes = diagonalM / targetPixels
  // 156543.03 * cosLat / 2^z = groundRes  ==>  z = log2(156543.03 * cosLat / groundRes)
  final groundRes = diagonalM / targetPixels;
  final rawZoom = math.log(156543.03 * cosLat / groundRes) / math.ln2;
  final zoom = rawZoom.clamp(12.0, 18.0);

  return PolygonBounds(center: LatLng(centerLat, centerLng), zoom: zoom);
}

double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusM = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180.0;
  final dLng = (lng2 - lng1) * math.pi / 180.0;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180.0) *
          math.cos(lat2 * math.pi / 180.0) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusM * c;
}
