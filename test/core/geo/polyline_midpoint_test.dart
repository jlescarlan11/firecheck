import 'package:firecheck/core/geo/polyline_midpoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('two-vertex line midpoint is the average of endpoints', () {
    final m = polylineMidpoint([
      [123.88200, 10.31720],
      [123.88340, 10.31900],
    ]);
    expect(m.lat, closeTo(10.31810, 1e-6));
    expect(m.lng, closeTo(123.88270, 1e-6));
  });

  test('multi-segment line returns midpoint by total length', () {
    // Three collinear points, equally spaced; midpoint is the middle vertex.
    final m = polylineMidpoint([
      [0.0, 0.0],
      [1.0, 1.0],
      [2.0, 2.0],
    ]);
    expect(m.lat, closeTo(1.0, 1e-6));
    expect(m.lng, closeTo(1.0, 1e-6));
  });

  test('decodes a GeoJSON LineString to its coordinate list', () {
    final coords = decodePolylineGeojson(
      '{"type":"LineString","coordinates":[[123.88200,10.31720],[123.88340,10.31900]]}',
    );
    expect(coords, isNotNull);
    expect(coords!.length, 2);
    expect(coords[0][0], 123.88200);
  });

  test('returns null for non-LineString geometry', () {
    final coords = decodePolylineGeojson(
      '{"type":"Point","coordinates":[0,0]}',
    );
    expect(coords, isNull);
  });
}
