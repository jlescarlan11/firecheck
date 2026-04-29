typedef LngLat = ({double lng, double lat});

// Identifies an intersecting pair of edges in the working outer ring.
// `aStart` and `bStart` index into rings[0]; the edge runs from index N to
// (N+1) % ringLength.
typedef EdgeIndex = ({int aStart, int bStart});

enum PolygonValidationError {
  tooFewVertices,
  zeroOrNegativeArea,
  selfIntersection,
  vertexOutsideBoundary,
  zeroLengthEdge,
}

class PolygonValidationResult {
  const PolygonValidationResult.valid()
      : valid = true,
        error = null,
        intersectingEdges = null;

  const PolygonValidationResult.invalid(
    this.error, {
    this.intersectingEdges,
  }) : valid = false;

  final bool valid;
  final PolygonValidationError? error;
  final List<EdgeIndex>? intersectingEdges;
}

/// Validates [rings] against the five reshape rules in declared order.
/// Short-circuits on the first failure.
///
/// `rings[0]` is the outer ring (open form: no duplicated end vertex).
/// Holes are not validated — building polygons only have an outer ring.
PolygonValidationResult validateBuildingPolygon(
  List<List<LngLat>> rings, {
  required String boundaryGeojson,
}) {
  if (rings.isEmpty) {
    return const PolygonValidationResult.invalid(
      PolygonValidationError.tooFewVertices,
    );
  }
  final outer = rings[0];

  // Rule 1: at least 3 unique vertices.
  if (_uniqueVertexCount(outer) < 3) {
    return const PolygonValidationResult.invalid(
      PolygonValidationError.tooFewVertices,
    );
  }

  // Rule 2: non-zero area (shoelace, in WGS84 sq-degrees; epsilon 1e-12).
  if (_signedArea(outer).abs() < 1e-12) {
    return const PolygonValidationResult.invalid(
      PolygonValidationError.zeroOrNegativeArea,
    );
  }

  // Rules 3, 4, 5 added in subsequent tasks.

  return const PolygonValidationResult.valid();
}

int _uniqueVertexCount(List<LngLat> ring) {
  final seen = <String>{};
  for (final v in ring) {
    seen.add('${v.lng.toStringAsFixed(9)},${v.lat.toStringAsFixed(9)}');
  }
  return seen.length;
}

double _signedArea(List<LngLat> ring) {
  if (ring.length < 3) return 0;
  var sum = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    sum += (b.lng - a.lng) * (b.lat + a.lat);
  }
  return sum / 2.0;
}
