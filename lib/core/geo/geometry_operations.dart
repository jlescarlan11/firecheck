import 'dart:convert';
import 'dart:math' as math;

import 'package:firecheck/core/geo/polygon_validator.dart' show LngLat;

typedef PolygonSplit = ({String firstGeojson, String secondGeojson});

PolygonSplit splitPolygonAtVertices(
  String geojson, {
  required int firstVertex,
  required int secondVertex,
}) {
  final ring = _polygonRing(geojson);
  final count = ring.length;
  if (count < 4) {
    throw const FormatException('A split requires at least four vertices');
  }
  if (firstVertex < 0 ||
      secondVertex < 0 ||
      firstVertex >= count ||
      secondVertex >= count) {
    throw RangeError('Split vertex is outside the polygon ring');
  }
  final distance = (firstVertex - secondVertex).abs();
  if (distance == 0 || distance == 1 || distance == count - 1) {
    throw const FormatException('Split vertices must be non-adjacent');
  }
  final low = math.min(firstVertex, secondVertex);
  final high = math.max(firstVertex, secondVertex);
  final first = ring.sublist(low, high + 1);
  final second = [...ring.sublist(high), ...ring.sublist(0, low + 1)];
  return (
    firstGeojson: _polygonGeojson(first),
    secondGeojson: _polygonGeojson(second),
  );
}

String mergeAdjacentPolygons(String firstGeojson, String secondGeojson) {
  final first = _polygonRing(firstGeojson);
  final second = _polygonRing(secondGeojson);
  final edges = <_Edge>[];
  void addRing(List<LngLat> ring) {
    for (var index = 0; index < ring.length; index++) {
      final edge = _Edge(ring[index], ring[(index + 1) % ring.length]);
      final reverse =
          edges.indexWhere((candidate) => candidate == edge.reverse);
      if (reverse >= 0) {
        edges.removeAt(reverse);
      } else {
        edges.add(edge);
      }
    }
  }

  addRing(first);
  final countBeforeSecond = edges.length;
  addRing(second);
  if (edges.length == countBeforeSecond + second.length) {
    throw const FormatException('Polygons do not share an edge');
  }

  final remaining = [...edges];
  final firstEdge = remaining.removeAt(0);
  final ring = <LngLat>[firstEdge.start, firstEdge.end];
  while (remaining.isNotEmpty) {
    final nextIndex = remaining.indexWhere((edge) => edge.start == ring.last);
    if (nextIndex < 0) {
      throw const FormatException('Merged boundary is not one simple polygon');
    }
    final next = remaining.removeAt(nextIndex);
    ring.add(next.end);
  }
  if (ring.last != ring.first) {
    throw const FormatException('Merged boundary does not close');
  }
  ring.removeLast();
  return _polygonGeojson(ring);
}

enum SnapTarget { vertex, edge }

typedef SnapResult = ({LngLat point, SnapTarget target, double distanceMeters});

SnapResult? snapToGeometry(
  LngLat point,
  Iterable<String> nearbyGeojson, {
  double toleranceMeters = 2,
}) {
  SnapResult? best;
  for (final geojson in nearbyGeojson) {
    final ring = _polygonRing(geojson);
    for (var index = 0; index < ring.length; index++) {
      final vertex = ring[index];
      best = _closer(best, point, vertex, SnapTarget.vertex, toleranceMeters);
      final projected = _projectToSegment(
        point,
        vertex,
        ring[(index + 1) % ring.length],
      );
      best = _closer(best, point, projected, SnapTarget.edge, toleranceMeters);
    }
  }
  return best;
}

SnapResult? _closer(
  SnapResult? current,
  LngLat source,
  LngLat candidate,
  SnapTarget target,
  double tolerance,
) {
  final distance = _distanceMeters(source, candidate);
  if (current != null &&
      current.target == SnapTarget.edge &&
      target == SnapTarget.vertex &&
      distance <= 0.5) {
    return (point: candidate, target: target, distanceMeters: distance);
  }
  if (current != null &&
      current.target == SnapTarget.vertex &&
      target == SnapTarget.edge &&
      current.distanceMeters <= 0.5) {
    return current;
  }
  if (distance > tolerance ||
      current != null && current.distanceMeters <= distance) {
    return current;
  }
  return (point: candidate, target: target, distanceMeters: distance);
}

LngLat _projectToSegment(LngLat point, LngLat start, LngLat end) {
  final meanLat = (start.lat + end.lat + point.lat) / 3;
  final scale = math.cos(meanLat * math.pi / 180);
  final px = point.lng * scale;
  final py = point.lat;
  final ax = start.lng * scale;
  final ay = start.lat;
  final bx = end.lng * scale;
  final by = end.lat;
  final dx = bx - ax;
  final dy = by - ay;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared == 0) return start;
  final t = (((px - ax) * dx + (py - ay) * dy) / lengthSquared).clamp(0.0, 1.0);
  return (lng: (ax + t * dx) / scale, lat: ay + t * dy);
}

double _distanceMeters(LngLat first, LngLat second) {
  final meanLat = (first.lat + second.lat) / 2 * math.pi / 180;
  final dx = (first.lng - second.lng) * math.cos(meanLat) * 111320;
  final dy = (first.lat - second.lat) * 111320;
  return math.sqrt(dx * dx + dy * dy);
}

List<LngLat> _polygonRing(String geojson) {
  final decoded = jsonDecode(geojson) as Map<String, dynamic>;
  if (decoded['type'] != 'Polygon') {
    throw const FormatException('Expected Polygon GeoJSON');
  }
  final coordinates = decoded['coordinates'] as List<dynamic>;
  if (coordinates.isEmpty) throw const FormatException('Polygon has no ring');
  final ring = (coordinates.first as List<dynamic>).map<LngLat>((raw) {
    final pair = raw as List<dynamic>;
    return (
      lng: (pair[0] as num).toDouble(),
      lat: (pair[1] as num).toDouble(),
    );
  }).toList();
  if (ring.length >= 2 && ring.first == ring.last) ring.removeLast();
  return ring;
}

String _polygonGeojson(List<LngLat> ring) => jsonEncode({
      'type': 'Polygon',
      'coordinates': [
        [...ring, ring.first].map((point) => [point.lng, point.lat]).toList(),
      ],
    });

class _Edge {
  const _Edge(this.start, this.end);

  final LngLat start;
  final LngLat end;
  _Edge get reverse => _Edge(end, start);

  @override
  bool operator ==(Object other) =>
      other is _Edge && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}
