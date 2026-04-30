// test/core/sync/shapefile/reprojector_test.dart
import 'package:firecheck/core/sync/shapefile/reprojector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Reprojector reprojector;

  setUp(() => reprojector = Reprojector());

  test('central-meridian easting maps to exactly 123° longitude', () {
    // (500000, y) in UTM 51N lies exactly on the 123°E central meridian.
    final result = reprojector.reproject(500000.0, 1000000.0);
    expect(result[0], closeTo(123.0, 0.001)); // longitude
    expect(result[1], closeTo(9.04, 0.05));   // latitude ~9°N
  });

  test('reprojectRing transforms all points in a ring', () {
    final ring = [
      [500000.0, 1000000.0],
      [501000.0, 1000000.0],
      [501000.0, 1001000.0],
      [500000.0, 1001000.0],
      [500000.0, 1000000.0],
    ];
    final result = reprojector.reprojectRing(ring);
    expect(result, hasLength(5));
    expect(result.first[0], closeTo(123.0, 0.01));
    expect(result.last[0], closeTo(123.0, 0.01));
  });
}
