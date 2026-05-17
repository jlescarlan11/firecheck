import 'package:firecheck/core/geo/polyline_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validatePolyline', () {
    test('returns null for two distinct vertices', () {
      final r = validatePolyline([
        (lng: 0.0, lat: 0.0),
        (lng: 1.0, lat: 0.0),
      ]);
      expect(r, isNull);
    });

    test('returns notEnoughVertices for fewer than 2', () {
      expect(validatePolyline([]), PolylineValidationError.notEnoughVertices);
      expect(validatePolyline([(lng: 0.0, lat: 0.0)]),
          PolylineValidationError.notEnoughVertices);
    });

    test('returns zeroLengthEdge when adjacent vertices are equal', () {
      final r = validatePolyline([
        (lng: 0.0, lat: 0.0),
        (lng: 0.0, lat: 0.0),
        (lng: 1.0, lat: 1.0),
      ]);
      expect(r, PolylineValidationError.zeroLengthEdge);
    });
  });
}
