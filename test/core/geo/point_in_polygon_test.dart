import 'package:firecheck/core/geo/point_in_polygon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Brgy. Tisa rectangle (centroid ~10.31810, 123.88270).
  const ring = [
    [123.88200, 10.31720],
    [123.88340, 10.31720],
    [123.88340, 10.31900],
    [123.88200, 10.31900],
    [123.88200, 10.31720],
  ];

  test('point clearly inside the rectangle', () {
    expect(pointInPolygon(10.31810, 123.88270, ring), isTrue);
  });

  test('point clearly outside (north) the rectangle', () {
    expect(pointInPolygon(10.40, 123.88270, ring), isFalse);
  });

  test('point clearly outside (south) the rectangle', () {
    expect(pointInPolygon(10.20, 123.88270, ring), isFalse);
  });

  test('decodes a GeoJSON Polygon and checks containment', () {
    const poly =
        '{"type":"Polygon","coordinates":[[[123.88200,10.31720],[123.88340,10.31720],[123.88340,10.31900],[123.88200,10.31900],[123.88200,10.31720]]]}';
    expect(pointInPolygonGeojson(10.31810, 123.88270, poly), isTrue);
    expect(pointInPolygonGeojson(10.40, 123.88270, poly), isFalse);
  });

  test('returns false for malformed GeoJSON', () {
    expect(pointInPolygonGeojson(10, 123, 'not-json'), isFalse);
    expect(pointInPolygonGeojson(10, 123, '{"type":"Point"}'), isFalse);
  });
}
