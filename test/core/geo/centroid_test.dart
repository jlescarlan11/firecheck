import 'package:firecheck/core/geo/centroid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('polygonCentroid', () {
    test('unit square centred at (0.5, 0.5)', () {
      const ring = [
        [0.0, 0.0],
        [1.0, 0.0],
        [1.0, 1.0],
        [0.0, 1.0],
        [0.0, 0.0],
      ];
      final c = polygonCentroid(ring);
      expect(c.lng, closeTo(0.5, 1e-9));
      expect(c.lat, closeTo(0.5, 1e-9));
    });

    test('right triangle (0,0)-(1,0)-(0,1) centroid is (1/3, 1/3)', () {
      const ring = [
        [0.0, 0.0],
        [1.0, 0.0],
        [0.0, 1.0],
        [0.0, 0.0],
      ];
      final c = polygonCentroid(ring);
      expect(c.lng, closeTo(1 / 3, 1e-9));
      expect(c.lat, closeTo(1 / 3, 1e-9));
    });

    test('clockwise vs counterclockwise yield same centroid', () {
      const ccw = [
        [0.0, 0.0],
        [2.0, 0.0],
        [2.0, 1.0],
        [0.0, 1.0],
        [0.0, 0.0],
      ];
      const cw = [
        [0.0, 0.0],
        [0.0, 1.0],
        [2.0, 1.0],
        [2.0, 0.0],
        [0.0, 0.0],
      ];
      final a = polygonCentroid(ccw);
      final b = polygonCentroid(cw);
      expect(a.lng, closeTo(b.lng, 1e-9));
      expect(a.lat, closeTo(b.lat, 1e-9));
    });

    test('Brgy. Tisa rectangle centroid', () {
      const ring = [
        [123.88200, 10.31720],
        [123.88340, 10.31720],
        [123.88340, 10.31900],
        [123.88200, 10.31900],
        [123.88200, 10.31720],
      ];
      final c = polygonCentroid(ring);
      expect(c.lng, closeTo(123.88270, 1e-5));
      expect(c.lat, closeTo(10.31810, 1e-5));
    });

    test('degenerate single-point ring returns that point', () {
      const ring = [
        [5.0, 7.0],
        [5.0, 7.0],
      ];
      final c = polygonCentroid(ring);
      expect(c.lng, 5.0);
      expect(c.lat, 7.0);
    });

    test('decodePolygonGeojson extracts the outer ring of a Polygon', () {
      const geojson = '{"type":"Polygon","coordinates":'
          '[[[123.88200,10.31720],[123.88340,10.31720],'
          '[123.88340,10.31900],[123.88200,10.31900],'
          '[123.88200,10.31720]]]}';
      final ring = decodePolygonGeojson(geojson);
      expect(ring, isNotNull);
      expect(ring!, hasLength(5));
      expect(ring.first, [123.88200, 10.31720]);
    });
  });
}
