import 'package:firecheck/core/geo/comparison_geometry.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

Polygon? decodeMapPolygon(String source) {
  final geometry = ComparisonGeometry.parse(source);
  if (geometry == null || geometry.type != 'Polygon') return null;
  return Polygon(
    coordinates: geometry.paths
        .map((ring) => ring.map((p) => Position(p.dx, p.dy)).toList())
        .toList(),
  );
}
