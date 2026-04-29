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

  // Rule 3: non-self-intersecting (open segments, ignore adjacent pairs).
  // Checked before area so a bowtie (zero net area due to self-intersection)
  // surfaces the more actionable selfIntersection error rather than zeroArea.
  final intersections = _findSelfIntersections(outer);
  if (intersections.isNotEmpty) {
    return PolygonValidationResult.invalid(
      PolygonValidationError.selfIntersection,
      intersectingEdges: intersections,
    );
  }

  // Rule 2: non-zero area (shoelace, in WGS84 sq-degrees; epsilon 1e-12).
  if (_signedArea(outer).abs() < 1e-12) {
    return const PolygonValidationResult.invalid(
      PolygonValidationError.zeroOrNegativeArea,
    );
  }

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

List<EdgeIndex> _findSelfIntersections(List<LngLat> ring) {
  final n = ring.length;
  final hits = <EdgeIndex>[];
  for (var i = 0; i < n; i++) {
    final a1 = ring[i];
    final a2 = ring[(i + 1) % n];
    for (var j = i + 1; j < n; j++) {
      // Skip adjacent edges (share a vertex) and the wraparound pair.
      if (j == i + 1) continue;
      if (i == 0 && j == n - 1) continue;
      final b1 = ring[j];
      final b2 = ring[(j + 1) % n];
      if (_segmentsIntersect(a1, a2, b1, b2)) {
        hits.add((aStart: i, bStart: j));
      }
    }
  }
  return hits;
}

// Standard CCW orientation test for open-segment intersection.
// Returns true iff the open segments (a1,a2) and (b1,b2) cross.
bool _segmentsIntersect(LngLat a1, LngLat a2, LngLat b1, LngLat b2) {
  final d1 = _ccw(b1, b2, a1);
  final d2 = _ccw(b1, b2, a2);
  final d3 = _ccw(a1, a2, b1);
  final d4 = _ccw(a1, a2, b2);

  if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
    return true;
  }
  // Collinear-touch cases are not considered self-intersection in this app —
  // only "transverse" crossings.
  return false;
}

double _ccw(LngLat p, LngLat q, LngLat r) {
  return (q.lng - p.lng) * (r.lat - p.lat) - (q.lat - p.lat) * (r.lng - p.lng);
}
