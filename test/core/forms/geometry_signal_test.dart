import 'package:firecheck/core/forms/geometry_signal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('geometrySignalFromGeojson', () {
    test('empty geojson yields empty-like signal', () {
      final s = geometrySignalFromGeojson('', featureType: 'building');
      expect(s.vertexCount, 0);
      expect(s.areaSqMeters, isNull);
      expect(s.lengthMeters, isNull);
    });

    test('Point → vertexCount 1', () {
      const g = '{"type":"Point","coordinates":[123.88,10.31]}';
      final s = geometrySignalFromGeojson(g, featureType: 'point');
      expect(s.vertexCount, 1);
    });

    test('LineString → vertexCount + non-zero length', () {
      const g =
          '{"type":"LineString","coordinates":[[123.88,10.31],[123.89,10.31]]}';
      final s = geometrySignalFromGeojson(g, featureType: 'road');
      expect(s.vertexCount, 2);
      expect(s.lengthMeters, isNotNull);
      expect(s.lengthMeters! > 0, isTrue);
      expect(s.areaSqMeters, isNull);
    });

    test('Polygon → vertexCount strips closing vertex + non-zero area', () {
      const g = '{"type":"Polygon","coordinates":[[[0,0],[0.001,0],[0.001,0.001],[0,0.001],[0,0]]]}';
      final s = geometrySignalFromGeojson(g, featureType: 'building');
      expect(s.vertexCount, 4);
      expect(s.areaSqMeters, isNotNull);
      expect(s.areaSqMeters! > 0, isTrue);
      expect(s.lengthMeters, isNull);
    });

    test('malformed geojson does not throw', () {
      final s = geometrySignalFromGeojson('not json', featureType: 'building');
      expect(s.vertexCount, 0);
    });

    test('equality treats identical signals as equal', () {
      const g = '{"type":"Point","coordinates":[1,2]}';
      final a = geometrySignalFromGeojson(g, featureType: 'point');
      final b = geometrySignalFromGeojson(g, featureType: 'point');
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
    });
  });
}
