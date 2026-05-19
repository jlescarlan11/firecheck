import 'dart:convert';

class LatLng {
  const LatLng({required this.lat, required this.lng});
  final double lat;
  final double lng;
}

/// Area-weighted centroid of a closed polygon ring (`[[lng, lat], ...]`).
/// Handles clockwise + counterclockwise. Falls back to the mean of the
/// points if the ring's signed area is degenerate (e.g. duplicated points).
LatLng polygonCentroid(List<List<double>> ring) {
  if (ring.isEmpty) return const LatLng(lat: 0, lng: 0);
  if (ring.length == 1) {
    return LatLng(lat: ring.first[1], lng: ring.first[0]);
  }

  double signedArea = 0;
  double cx = 0;
  double cy = 0;

  for (var i = 0; i < ring.length - 1; i++) {
    final x0 = ring[i][0];
    final y0 = ring[i][1];
    final x1 = ring[i + 1][0];
    final y1 = ring[i + 1][1];
    final cross = x0 * y1 - x1 * y0;
    signedArea += cross;
    cx += (x0 + x1) * cross;
    cy += (y0 + y1) * cross;
  }
  signedArea /= 2;

  if (signedArea.abs() < 1e-12) {
    double sx = 0;
    double sy = 0;
    for (final p in ring) {
      sx += p[0];
      sy += p[1];
    }
    return LatLng(lat: sy / ring.length, lng: sx / ring.length);
  }

  cx /= 6 * signedArea;
  cy /= 6 * signedArea;
  return LatLng(lat: cy, lng: cx);
}

/// Best-effort GeoJSON decode. Returns the first (outer) ring of a Polygon
/// as a list of `[lng, lat]` pairs, or null if the input isn't a parseable
/// Polygon. Holes are ignored.
List<List<double>>? decodePolygonGeojson(String geojson) {
  if (geojson.isEmpty) return null;
  try {
    final decoded = jsonDecode(geojson);
    if (decoded is! Map<String, Object?>) return null;
    final coords = decoded['coordinates'];
    if (coords is! List<Object?> || coords.isEmpty) return null;
    final outer = coords.first;
    if (outer is! List<Object?>) return null;
    final out = <List<double>>[];
    for (final p in outer) {
      if (p is! List<Object?> || p.length < 2) return null;
      final lng = p[0];
      final lat = p[1];
      if (lng is! num || lat is! num) return null;
      out.add([lng.toDouble(), lat.toDouble()]);
    }
    return out;
  } on Object {
    return null;
  }
}
