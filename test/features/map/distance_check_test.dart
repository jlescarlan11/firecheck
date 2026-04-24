import 'package:firecheck/features/map/domain/distance_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('distanceCheck', () {
    test('returns Pass when within 50m', () {
      final result = distanceCheck(
        userLat: 10.31810,
        userLng: 123.88270,
        featureCentroidLat: 10.31810,
        featureCentroidLng: 123.88275, // ~5m east
      );
      expect(result, isA<DistanceCheckPass>());
      expect((result as DistanceCheckPass).meters, lessThan(50));
    });

    test('returns Fail with distance when beyond 50m', () {
      final result = distanceCheck(
        userLat: 10.31810,
        userLng: 123.88270,
        featureCentroidLat: 10.31810,
        featureCentroidLng: 123.89270, // ~1km east
      );
      expect(result, isA<DistanceCheckFail>());
      expect((result as DistanceCheckFail).meters, greaterThan(50));
    });

    test('exactly at 50m is a Pass (boundary is inclusive)', () {
      // Degree of longitude at lat 10.318 ≈ 109.25 km. 50m ≈ 4.576e-4 deg.
      final result = distanceCheck(
        userLat: 10.31810,
        userLng: 123.88270,
        featureCentroidLat: 10.31810,
        featureCentroidLng: 123.88270 + 4.576e-4,
      );
      expect(result, isA<DistanceCheckPass>());
    });
  });
}
