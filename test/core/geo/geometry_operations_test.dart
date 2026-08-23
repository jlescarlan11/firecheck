import 'dart:convert';

import 'package:firecheck/core/geo/geometry_operations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rectangle =
      '{"type":"Polygon","coordinates":[[[0,0],[2,0],[2,1],[0,1],[0,0]]]}';

  test('split creates two closed polygons along non-adjacent vertices', () {
    final split = splitPolygonAtVertices(
      rectangle,
      firstVertex: 0,
      secondVertex: 2,
    );
    final first = jsonDecode(split.firstGeojson) as Map<String, dynamic>;
    final second = jsonDecode(split.secondGeojson) as Map<String, dynamic>;
    expect(((first['coordinates'] as List).first as List).length, 4);
    expect(((second['coordinates'] as List).first as List).length, 4);
  });

  test('split rejects an edge because it cannot make two polygons', () {
    expect(
      () => splitPolygonAtVertices(
        rectangle,
        firstVertex: 0,
        secondVertex: 1,
      ),
      throwsFormatException,
    );
  });

  test('merge removes a shared edge and returns one outer boundary', () {
    const other =
        '{"type":"Polygon","coordinates":[[[2,0],[3,0],[3,1],[2,1],[2,0]]]}';
    final merged = jsonDecode(mergeAdjacentPolygons(rectangle, other))
        as Map<String, dynamic>;
    final ring = (merged['coordinates'] as List).first as List;
    expect(ring.first, ring.last);
    expect(ring.length, 7);
  });

  test('merge rejects polygons without a shared edge', () {
    const detached =
        '{"type":"Polygon","coordinates":[[[3,0],[4,0],[4,1],[3,1],[3,0]]]}';
    expect(
      () => mergeAdjacentPolygons(rectangle, detached),
      throwsFormatException,
    );
  });

  test('snap prefers a nearby vertex over a farther edge', () {
    final result = snapToGeometry(
      (lng: 2.000001, lat: 0.000001),
      const [rectangle],
      toleranceMeters: 2,
    );
    expect(result, isNotNull);
    expect(result!.target, SnapTarget.vertex);
    expect(result.point, (lng: 2, lat: 0));
  });

  test('snap projects onto a nearby edge', () {
    final result = snapToGeometry(
      (lng: 1, lat: 0.000005),
      const [rectangle],
      toleranceMeters: 2,
    );
    expect(result, isNotNull);
    expect(result!.target, SnapTarget.edge);
    expect(result.point.lat, closeTo(0, 1e-12));
  });
}
