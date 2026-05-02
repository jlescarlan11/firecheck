import 'dart:convert';

import 'package:firecheck/core/geo/centroid.dart';

/// Midpoint of a polyline measured by cumulative segment length.
/// `coords` is `[[lng, lat], ...]` (GeoJSON ordering).
LatLng polylineMidpoint(List<List<double>> coords) {
  if (coords.isEmpty) {
    throw ArgumentError('coords must not be empty');
  }
  if (coords.length == 1) {
    return LatLng(lat: coords[0][1], lng: coords[0][0]);
  }

  final segLengths = <double>[];
  double total = 0;
  for (var i = 0; i < coords.length - 1; i++) {
    final dx = coords[i + 1][0] - coords[i][0];
    final dy = coords[i + 1][1] - coords[i][1];
    final len = dx * dx + dy * dy;
    segLengths.add(len);
    total += len;
  }

  final half = total / 2;
  double accumulated = 0;
  for (var i = 0; i < segLengths.length; i++) {
    if (accumulated + segLengths[i] >= half) {
      final remainingFraction =
          segLengths[i] == 0 ? 0.0 : (half - accumulated) / segLengths[i];
      final lng = coords[i][0] +
          remainingFraction * (coords[i + 1][0] - coords[i][0]);
      final lat = coords[i][1] +
          remainingFraction * (coords[i + 1][1] - coords[i][1]);
      return LatLng(lat: lat, lng: lng);
    }
    accumulated += segLengths[i];
  }

  // Fallback (shouldn't reach): last vertex.
  return LatLng(lat: coords.last[1], lng: coords.last[0]);
}

/// Decodes a GeoJSON LineString into its coordinate ring. Returns null for
/// non-LineString geometries, malformed JSON, or fewer than 2 coordinates.
List<List<double>>? decodePolylineGeojson(String geojson) {
  try {
    final parsed = jsonDecode(geojson) as Map<String, dynamic>;
    if (parsed['type'] != 'LineString') return null;
    final coords = parsed['coordinates'] as List<dynamic>;
    if (coords.length < 2) return null;
    return coords
        .map(
          (p) =>
              (p as List<dynamic>).map((v) => (v as num).toDouble()).toList(),
        )
        .toList();
  } on Object {
    return null;
  }
}
