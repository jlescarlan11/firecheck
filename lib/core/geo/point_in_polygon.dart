import 'dart:convert';

/// Ray-casting point-in-polygon test. `ring` is `[[lng, lat], ...]`.
/// Edge / vertex behavior is implementation-defined and acceptable for the
/// boundary-check use case (we just want to reject taps clearly outside).
bool pointInPolygon(double lat, double lng, List<List<double>> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final xi = ring[i][0];
    final yi = ring[i][1];
    final xj = ring[j][0];
    final yj = ring[j][1];
    final intersect = ((yi > lat) != (yj > lat)) &&
        (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

/// Convenience: decode a GeoJSON Polygon and run [pointInPolygon] against
/// its outer ring. Returns false on malformed input or non-Polygon types.
bool pointInPolygonGeojson(double lat, double lng, String geojson) {
  try {
    final parsed = jsonDecode(geojson) as Map<String, dynamic>;
    if (parsed['type'] != 'Polygon') return false;
    final coords = parsed['coordinates'] as List;
    if (coords.isEmpty) return false;
    final ring = (coords[0] as List)
        .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
        .toList();
    return pointInPolygon(lat, lng, ring);
  } on Object {
    return false;
  }
}
