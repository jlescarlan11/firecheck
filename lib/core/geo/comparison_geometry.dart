import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Validated geometry, independent of basemap tiles or native map credentials.
class ComparisonGeometry {
  ComparisonGeometry._(this.type, this.paths, this.source);
  final String source;
  final String type;
  final List<List<Offset>> paths;

  static ComparisonGeometry? parse(String source) {
    try {
      final json = jsonDecode(source) as Map<String, dynamic>;
      final type = json['type'] as String;
      Offset point(dynamic value) {
        final p = value as List;
        final x = (p[0] as num).toDouble();
        final y = (p[1] as num).toDouble();
        if (!x.isFinite || !y.isFinite || x.abs() > 180 || y.abs() > 90) {
          throw const FormatException('Invalid position');
        }
        return Offset(x, y);
      }

      List<Offset> line(dynamic value, {bool ring = false}) {
        final points = (value as List).map(point).toList();
        if (points.length < (ring ? 4 : 2) ||
            (ring &&
                (points.first != points.last || points.toSet().length < 3))) {
          throw const FormatException('Incomplete geometry');
        }
        if (points.toSet().length < (ring ? 3 : 2)) {
          throw const FormatException('Degenerate geometry');
        }
        if (ring) {
          final origin = points.first;
          var twiceArea = 0.0;
          for (var i = 1; i < points.length; i++) {
            final a = points[i - 1] - origin;
            final b = points[i] - origin;
            twiceArea += a.dx * b.dy - b.dx * a.dy;
          }
          if (twiceArea == 0) throw const FormatException('Zero area');
        }
        return points;
      }

      List<List<Offset>> polygon(dynamic value) {
        final rings = (value as List).map((r) => line(r, ring: true)).toList();
        if (rings.isEmpty) throw const FormatException('Empty polygon');
        return rings;
      }

      final coordinates = json['coordinates'];
      final paths = switch (type) {
        'Point' => [
            [point(coordinates)],
          ],
        'LineString' => [line(coordinates)],
        'Polygon' => polygon(coordinates),
        'MultiPolygon' => (coordinates as List).expand(polygon).toList(),
        _ => throw const FormatException('Unsupported geometry'),
      };
      if (paths.isEmpty) return null;
      return ComparisonGeometry._(type, paths, source);
    } on Object {
      return null;
    }
  }
}

/// A common, aspect-preserving local projection fits both geometries together.
class ComparisonProjection {
  ComparisonProjection(Iterable<ComparisonGeometry> geometries, this.size) {
    final points = geometries.expand((g) => g.paths.expand((p) => p)).toList();
    final latitude =
        points.map((p) => p.dy).reduce((a, b) => a + b) / points.length;
    _longitudeScale = math.max(0.000001, math.cos(latitude * math.pi / 180));
    final projected = points.map((p) => Offset(p.dx * _longitudeScale, -p.dy));
    _bounds = projected
        .map((p) => Rect.fromPoints(p, p))
        .reduce((a, b) => a.expandToInclude(b));
    _scale = math.min(
      (size.width - 32) / math.max(_bounds.width, 0.000001),
      (size.height - 32) / math.max(_bounds.height, 0.000001),
    );
  }
  final Size size;
  late final double _longitudeScale;
  late final Rect _bounds;
  late final double _scale;
  Offset project(Offset point) =>
      (Offset(point.dx * _longitudeScale, -point.dy) - _bounds.center) *
          _scale +
      size.center(Offset.zero);
}
