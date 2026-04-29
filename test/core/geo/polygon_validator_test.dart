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

  group('rule 3 — selfIntersection', () {
    test('passes for a simple convex quad', () {
      final result = validateBuildingPolygon(
        [
          [
            (lng: 123.880, lat: 10.320),
            (lng: 123.881, lat: 10.320),
            (lng: 123.881, lat: 10.321),
            (lng: 123.880, lat: 10.321),
          ],
        ],
        boundaryGeojson: boundary,
      );
      expect(result.valid, isTrue);
    });

    test('fails for a bowtie (4 vertices crossing)', () {
      // Vertices ordered so edges 0-1 and 2-3 cross.
      final result = validateBuildingPolygon(
        [
          [
            (lng: 123.880, lat: 10.320),
            (lng: 123.881, lat: 10.321),
            (lng: 123.881, lat: 10.320),
            (lng: 123.880, lat: 10.321),
          ],
        ],
        boundaryGeojson: boundary,
      );
      expect(result.valid, isFalse);
      expect(result.error, PolygonValidationError.selfIntersection);
      expect(result.intersectingEdges, isNotNull);
      expect(result.intersectingEdges!.isNotEmpty, isTrue);
      // Bowtie edge pairs in this 4-vertex layout: (0,2).
      expect(
        result.intersectingEdges!.any(
          (e) => (e.aStart == 0 && e.bStart == 2) || (e.aStart == 2 && e.bStart == 0),
        ),
        isTrue,
      );
    });

    test('does not report adjacent edges as intersecting', () {
      // Plain triangle — adjacent edges share endpoints, must not flag.
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
    });
  });

  group('rule 4 — vertexOutsideBoundary', () {
    test('passes when all vertices are inside boundary', () {
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
    });

    test('fails when one vertex is outside boundary', () {
      final result = validateBuildingPolygon(
        [
          [
            (lng: 123.880, lat: 10.320),
            (lng: 124.000, lat: 10.320), // way outside
            (lng: 123.880, lat: 10.321),
          ],
        ],
        boundaryGeojson: boundary,
      );
      expect(result.valid, isFalse);
      expect(result.error, PolygonValidationError.vertexOutsideBoundary);
    });
  });

  group('rule 5 — zeroLengthEdge', () {
    test('fails when two adjacent vertices are coincident', () {
      final result = validateBuildingPolygon(
        [
          [
            (lng: 123.880, lat: 10.320),
            (lng: 123.880, lat: 10.320), // duplicate
            (lng: 123.881, lat: 10.320),
            (lng: 123.880, lat: 10.321),
          ],
        ],
        boundaryGeojson: boundary,
      );
      expect(result.valid, isFalse);
      expect(result.error, PolygonValidationError.zeroLengthEdge);
    });

    test('passes when adjacent vertices are 1cm apart (above epsilon)', () {
      // ~1e-7 degrees is ~1cm at the equator — well above 1e-9 epsilon.
      final result = validateBuildingPolygon(
        [
          [
            (lng: 123.880, lat: 10.320),
            (lng: 123.8800001, lat: 10.320), // 1cm east
            (lng: 123.881, lat: 10.320),
            (lng: 123.880, lat: 10.321),
          ],
        ],
        boundaryGeojson: boundary,
      );
      expect(result.valid, isTrue);
    });
  });

  group('rule ordering', () {
    test('returns rule 1 when polygon also fails rule 3', () {
      // 2 vertices fails rule 1; can't fail rule 3 simultaneously, so build
      // a case that fails rule 1 + rule 5. Two vertices, both coincident.
      final result = validateBuildingPolygon(
        [
          [
            (lng: 123.880, lat: 10.320),
            (lng: 123.880, lat: 10.320),
          ],
        ],
        boundaryGeojson: boundary,
      );
      expect(result.error, PolygonValidationError.tooFewVertices);
    });
  });
}
