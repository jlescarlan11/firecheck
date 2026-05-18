// lib/core/forms/geometry_signal.dart
//
// Geometry-derived summary that feeds form skip-logic (Issue #44). The
// signal is recomputed every time the underlying feature's geojson changes
// — e.g. after a reshape — so any skip rule that depends on the shape
// (area thresholds, length thresholds, vertex counts) re-evaluates without
// the user re-opening the form.
//
// Today's applicability rules don't actually consume the signal yet, but
// every entry point already routes it through so adding a new geometry-
// dependent rule is a one-line change in the applicability function.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

@immutable
class GeometrySignal {
  const GeometrySignal({
    required this.featureType,
    required this.vertexCount,
    this.areaSqMeters,
    this.lengthMeters,
  });

  /// Signal for an unknown / unparseable geometry. Skip rules should treat
  /// this as "no geometry yet" — never as "geometry says no".
  static const GeometrySignal empty =
      GeometrySignal(featureType: 'unknown', vertexCount: 0);

  /// 'building' | 'road' | 'point' | 'unknown'.
  final String featureType;
  final int vertexCount;

  /// Surface area in m² for closed shapes. Null for polylines and points.
  final double? areaSqMeters;

  /// Length in meters for polylines. Null for closed shapes and points.
  final double? lengthMeters;

  @override
  bool operator ==(Object other) =>
      other is GeometrySignal &&
      other.featureType == featureType &&
      other.vertexCount == vertexCount &&
      other.areaSqMeters == areaSqMeters &&
      other.lengthMeters == lengthMeters;

  @override
  int get hashCode =>
      Object.hash(featureType, vertexCount, areaSqMeters, lengthMeters);
}

/// Derives a [GeometrySignal] from a GeoJSON string. Returns
/// [GeometrySignal.empty] for unparseable input — callers should not retry
/// or surface the failure; an unparseable feature is upstream's problem.
GeometrySignal geometrySignalFromGeojson(
  String geojson, {
  required String featureType,
}) {
  if (geojson.isEmpty) {
    return GeometrySignal(featureType: featureType, vertexCount: 0);
  }
  try {
    final m = jsonDecode(geojson) as Map<String, dynamic>;
    final type = m['type'] as String;
    final coords = m['coordinates'] as List;
    switch (type) {
      case 'Point':
        return GeometrySignal(featureType: featureType, vertexCount: 1);
      case 'LineString':
        final line = coords
            .map<List<double>>(
              (p) => (p as List)
                  .map<double>((v) => (v as num).toDouble())
                  .toList(),
            )
            .toList();
        return GeometrySignal(
          featureType: featureType,
          vertexCount: line.length,
          lengthMeters: _polylineMeters(line),
        );
      case 'Polygon':
        final ring = (coords.first as List)
            .map<List<double>>(
              (p) => (p as List)
                  .map<double>((v) => (v as num).toDouble())
                  .toList(),
            )
            .toList();
        // Drop the duplicated closing vertex if present.
        final open = (ring.length >= 2 &&
                ring.first[0] == ring.last[0] &&
                ring.first[1] == ring.last[1])
            ? ring.sublist(0, ring.length - 1)
            : ring;
        return GeometrySignal(
          featureType: featureType,
          vertexCount: open.length,
          areaSqMeters: _polygonAreaSqMeters(open),
        );
      default:
        return GeometrySignal(featureType: featureType, vertexCount: 0);
    }
  } catch (_) {
    return GeometrySignal(featureType: featureType, vertexCount: 0);
  }
}

double _polylineMeters(List<List<double>> coords) {
  if (coords.length < 2) return 0;
  double total = 0;
  for (var i = 0; i < coords.length - 1; i++) {
    total += _haversineMeters(
      coords[i][1],
      coords[i][0],
      coords[i + 1][1],
      coords[i + 1][0],
    );
  }
  return total;
}

/// Equirectangular projection scaled by the ring's mean latitude — accurate
/// enough for building-scale polygons and avoids dragging in a heavyweight
/// geodesy dep. Returns absolute area in m².
double _polygonAreaSqMeters(List<List<double>> ring) {
  if (ring.length < 3) return 0;
  final mean =
      ring.map((p) => p[1]).reduce((a, b) => a + b) / ring.length;
  final cosLat = math.cos(mean * math.pi / 180.0);
  const metersPerDegreeLat = 111320.0;
  double sum = 0;
  for (var i = 0; i < ring.length; i++) {
    final j = (i + 1) % ring.length;
    final xi = ring[i][0] * cosLat * metersPerDegreeLat;
    final yi = ring[i][1] * metersPerDegreeLat;
    final xj = ring[j][0] * cosLat * metersPerDegreeLat;
    final yj = ring[j][1] * metersPerDegreeLat;
    sum += xi * yj - xj * yi;
  }
  return (sum.abs()) / 2.0;
}

double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180.0;
  final dLng = (lng2 - lng1) * math.pi / 180.0;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180.0) *
          math.cos(lat2 * math.pi / 180.0) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadius * c;
}
