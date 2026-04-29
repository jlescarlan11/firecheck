import 'package:firecheck/core/geo/polygon_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Brgy. Tisa rectangle (reused throughout the project — see
  // override_check_test.dart). All vertices well inside this boundary.
  const boundary = '''
{"type":"Polygon","coordinates":[[
  [123.870,10.310],[123.890,10.310],[123.890,10.330],[123.870,10.330],[123.870,10.310]
]]}''';

  group('rule 1 — tooFewVertices', () {
    test('passes with 3 unique vertices', () {
      final result = validateBuildingPolygon(
        [
          [
            (lng: 123.880, lat: 10.320),
            (lng: 123.881, lat: 10.320),
            (lng: 123.880, lat: 10.321),
          ],
        ],
        boundaryGeojson: boundary,
      );
      expect(result.valid, isTrue);
      expect(result.error, isNull);
    });

    test('fails with 2 unique vertices', () {
      final result = validateBuildingPolygon(
        [
          [
            (lng: 123.880, lat: 10.320),
            (lng: 123.881, lat: 10.320),
          ],
        ],
        boundaryGeojson: boundary,
      );
      expect(result.valid, isFalse);
      expect(result.error, PolygonValidationError.tooFewVertices);
    });
  });

  group('rule 2 — zeroOrNegativeArea', () {
    test('fails for colinear vertices', () {
      final result = validateBuildingPolygon(
        [
          [
            (lng: 123.880, lat: 10.320),
            (lng: 123.881, lat: 10.320),
            (lng: 123.882, lat: 10.320),
          ],
        ],
        boundaryGeojson: boundary,
      );
      expect(result.valid, isFalse);
      expect(result.error, PolygonValidationError.zeroOrNegativeArea);
    });
  });
}
