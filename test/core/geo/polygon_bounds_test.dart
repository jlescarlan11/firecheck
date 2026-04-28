import 'package:firecheck/core/geo/polygon_bounds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('polygonBoundsFromGeojson', () {
    test('returns null for empty string', () {
      expect(polygonBoundsFromGeojson(''), isNull);
    });

    test('returns null for malformed JSON', () {
      expect(polygonBoundsFromGeojson('not json'), isNull);
    });

    test('returns null for non-Polygon types', () {
      expect(
        polygonBoundsFromGeojson('{"type":"Point","coordinates":[0,0]}'),
        isNull,
      );
    });

    test('computes centroid of a small square polygon', () {
      // 0.001° square (~111m on a side) around (10.31810, 123.88270)
      // GeoJSON coords are [lng, lat]
      const geojson = '''
{"type":"Polygon","coordinates":[[
  [123.882, 10.317],
  [123.884, 10.317],
  [123.884, 10.319],
  [123.882, 10.319],
  [123.882, 10.317]
]]}''';
      final bounds = polygonBoundsFromGeojson(geojson);
      expect(bounds, isNotNull);
      expect(bounds!.center.lat, closeTo(10.318, 1e-6));
      expect(bounds.center.lng, closeTo(123.883, 1e-6));
    });

    test('zoom is clamped to 18 for tiny polygons', () {
      // ~10m square — well below the zoom-18 ground resolution
      const geojson = '''
{"type":"Polygon","coordinates":[[
  [123.88270, 10.31810],
  [123.88280, 10.31810],
  [123.88280, 10.31820],
  [123.88270, 10.31820],
  [123.88270, 10.31810]
]]}''';
      final bounds = polygonBoundsFromGeojson(geojson)!;
      expect(bounds.zoom, 18.0);
    });

    test('zoom is clamped to 12 for huge polygons', () {
      // ~10° span — covers half a country
      const geojson = '''
{"type":"Polygon","coordinates":[[
  [120.0, 5.0],
  [130.0, 5.0],
  [130.0, 15.0],
  [120.0, 15.0],
  [120.0, 5.0]
]]}''';
      final bounds = polygonBoundsFromGeojson(geojson)!;
      expect(bounds.zoom, 12.0);
    });

    test('zoom is monotonic with bounding-box size', () {
      String squareJson(double size) {
        const lat = 10.318;
        const lng = 123.883;
        final h = size / 2;
        return '{"type":"Polygon","coordinates":[[ '
            '[${lng - h},${lat - h}], '
            '[${lng + h},${lat - h}], '
            '[${lng + h},${lat + h}], '
            '[${lng - h},${lat + h}], '
            '[${lng - h},${lat - h}]]]}';
      }

      final small = polygonBoundsFromGeojson(squareJson(0.001))!;
      final medium = polygonBoundsFromGeojson(squareJson(0.01))!;
      final large = polygonBoundsFromGeojson(squareJson(0.1))!;

      expect(small.zoom >= medium.zoom, isTrue);
      expect(medium.zoom >= large.zoom, isTrue);
    });
  });
}
