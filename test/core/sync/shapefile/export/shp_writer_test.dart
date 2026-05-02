// test/core/sync/shapefile/export/shp_writer_test.dart
import 'dart:typed_data';

import 'package:firecheck/core/sync/shapefile/export/shp_writer.dart';
import 'package:firecheck/core/sync/shapefile/shp_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const writer = ShpWriter();
  const parser = ShpParser();

  group('ShpWriter — polygons', () {
    final ring = [
      [120.0, 14.0],
      [121.0, 14.0],
      [121.0, 15.0],
      [120.0, 15.0],
      [120.0, 14.0],
    ];

    test('round-trip: written polygon parses back with matching coordinates', () {
      final result = writer.writePolygons([[ring]]);
      final geometries = parser.parse(result.shp);

      expect(geometries, hasLength(1));
      final poly = geometries.first as ShpPolygon;
      expect(poly.rings, hasLength(1));
      expect(poly.rings.first, hasLength(ring.length));
      for (var i = 0; i < ring.length; i++) {
        expect(poly.rings.first[i][0], closeTo(ring[i][0], 0.0001));
        expect(poly.rings.first[i][1], closeTo(ring[i][1], 0.0001));
      }
    });

    test('bounding box in file header matches feature extents', () {
      final result = writer.writePolygons([[ring]]);
      final data = result.shp.buffer.asByteData();

      final minX = data.getFloat64(36, Endian.little);
      final minY = data.getFloat64(44, Endian.little);
      final maxX = data.getFloat64(52, Endian.little);
      final maxY = data.getFloat64(60, Endian.little);

      expect(minX, closeTo(120.0, 0.0001));
      expect(minY, closeTo(14.0, 0.0001));
      expect(maxX, closeTo(121.0, 0.0001));
      expect(maxY, closeTo(15.0, 0.0001));
    });

    test('shx offsets correctly index each record', () {
      final ring2 = [
        [122.0, 16.0],
        [123.0, 16.0],
        [123.0, 17.0],
        [122.0, 16.0],
      ];
      final result = writer.writePolygons([[ring], [ring2]]);
      final shpData = result.shp.buffer.asByteData();
      final shxData = result.shx.buffer.asByteData();

      final offset0 = shxData.getInt32(100, Endian.big) * 2;
      expect(offset0, equals(100));

      final offset1 = shxData.getInt32(108, Endian.big) * 2;
      final contentWords = shpData.getInt32(offset1 + 4, Endian.big);
      expect(contentWords, greaterThan(0));
    });

    test('empty geometry list produces header-only SHP with zeroed bbox', () {
      final result = writer.writePolygons([]);
      expect(result.shp.length, equals(100));
      expect(result.shx.length, equals(100));

      final data = result.shp.buffer.asByteData();
      expect(data.getFloat64(36, Endian.little), equals(0.0)); // minX
      expect(data.getFloat64(44, Endian.little), equals(0.0)); // minY
      expect(data.getFloat64(52, Endian.little), equals(0.0)); // maxX
      expect(data.getFloat64(60, Endian.little), equals(0.0)); // maxY
    });
  });

  group('ShpWriter — polylines', () {
    final part = [
      [120.0, 14.0],
      [121.0, 14.5],
      [122.0, 14.0],
    ];

    test('round-trip: written polyline parses back with matching coordinates', () {
      final result = writer.writePolylines([[part]]);
      final geometries = parser.parse(result.shp);

      expect(geometries, hasLength(1));
      final line = geometries.first as ShpPolyline;
      expect(line.parts.first, hasLength(part.length));
      for (var i = 0; i < part.length; i++) {
        expect(line.parts.first[i][0], closeTo(part[i][0], 0.0001));
        expect(line.parts.first[i][1], closeTo(part[i][1], 0.0001));
      }
    });
  });
}
