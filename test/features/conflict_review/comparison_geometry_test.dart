import 'package:firecheck/core/geo/comparison_geometry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('point line polygon share bounds and fit degenerate extents safely', () {
    final point =
        ComparisonGeometry.parse('{"type":"Point","coordinates":[0,0]}')!;
    final line = ComparisonGeometry.parse(
      '{"type":"LineString","coordinates":[[0,0],[2,0]]}',
    )!;
    final p = ComparisonProjection([point, line], const Size(200, 200));
    expect(p.project(Offset.zero), const Offset(16, 100));
    expect(p.project(const Offset(2, 0)), const Offset(184, 100));
    final coincident =
        ComparisonProjection([point, point], const Size(200, 200));
    expect(coincident.project(Offset.zero), const Offset(100, 100));
  });
  test('reject zero-area rings and repeated-position roads', () {
    expect(
      ComparisonGeometry.parse(
        '{"type":"Polygon","coordinates":[[[0,0],[1,0],[2,0],[0,0]]]}',
      ),
      isNull,
    );
    expect(
      ComparisonGeometry.parse(
        '{"type":"LineString","coordinates":[[1,1],[1,1]]}',
      ),
      isNull,
    );
  });
  test('supports polygon holes and imported multi-polygons', () {
    final polygon = ComparisonGeometry.parse(
      '{"type":"Polygon","coordinates":[[[0,0],[4,0],[4,4],[0,0]],[[1,1],[2,1],[2,2],[1,1]]]}',
    );
    final multi = ComparisonGeometry.parse(
      '{"type":"MultiPolygon","coordinates":[[[[0,0],[1,0],[1,1],[0,0]]],[[[2,2],[3,2],[3,3],[2,2]]]]}',
    );
    expect(polygon!.paths, hasLength(2));
    expect(multi!.paths, hasLength(2));
  });
  test('reject malformed unsupported and out-of-range positions', () {
    for (final input in [
      'bad',
      '{"type":"Point","coordinates":[181,0]}',
      '{"type":"LineString","coordinates":[[0,0]]}',
      '{"type":"Polygon","coordinates":[]}',
      '{"type":"GeometryCollection","geometries":[]}',
    ]) {
      expect(ComparisonGeometry.parse(input), isNull);
    }
  });
}
