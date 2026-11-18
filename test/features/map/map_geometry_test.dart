import 'package:firecheck/features/map/presentation/map_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'rejects unclosed and empty polygons instead of drawing misleading boundary',
      () {
    expect(
      decodeMapPolygon(
        '{"type":"Polygon","coordinates":[[[0,0],[1,0],[0,1]]]}',
      ),
      isNull,
    );
    expect(decodeMapPolygon('{"type":"Polygon","coordinates":[]}'), isNull);
    expect(
      decodeMapPolygon(
        '{"type":"MultiLineString","coordinates":[[[0,0],[1,0],[0,1],[0,0]]]}',
      ),
      isNull,
    );
  });
}
