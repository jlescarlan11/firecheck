import 'package:firecheck/core/location/distance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('haversineMeters', () {
    test('zero distance between same coordinates', () {
      expect(haversineMeters(10.0, 20.0, 10.0, 20.0), 0.0);
    });

    test('approx 111 km per degree of latitude at the equator', () {
      final d = haversineMeters(0.0, 0.0, 1.0, 0.0);
      expect(d, closeTo(111195, 500));
    });

    test(
        'Cebu City (approx 10.3, 123.9) to Manila (approx 14.6, 121.0) is ~570 km',
        () {
      final d = haversineMeters(10.3157, 123.8854, 14.5995, 120.9842);
      expect(d / 1000, closeTo(571, 10));
    });

    test('antipodal points are ~half-earth-circumference apart', () {
      final d = haversineMeters(0.0, 0.0, 0.0, 180.0);
      // Earth's circumference is ~40,075 km; half is ~20,037 km.
      expect(d / 1000, closeTo(20037, 50));
    });

    test('is symmetric', () {
      final a = haversineMeters(10.3, 123.9, 10.4, 123.8);
      final b = haversineMeters(10.4, 123.8, 10.3, 123.9);
      expect(a, b);
    });

    test('returns non-negative for small diffs', () {
      // 1 arcsecond at 10 degrees latitude
      final d = haversineMeters(10.0, 20.0, 10.0 + 1 / 3600, 20.0);
      expect(d, greaterThan(0));
      expect(d, closeTo(30.9, 1.0));
    });
  });
}
