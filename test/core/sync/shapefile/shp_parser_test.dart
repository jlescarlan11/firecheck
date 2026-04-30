// test/core/sync/shapefile/shp_parser_test.dart
import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/shp_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a minimal SHP containing a single polygon or polyline.
Uint8List buildPolygonShp(List<List<List<double>>> rings) {
  return _buildShp(shapeType: 5, parts: rings);
}

Uint8List buildPolylineShp(List<List<List<double>>> parts) {
  return _buildShp(shapeType: 3, parts: parts);
}

Uint8List _buildShp({
  required int shapeType,
  required List<List<List<double>>> parts,
}) {
  final totalPoints = parts.fold(0, (s, r) => s + r.length);
  final numParts = parts.length;
  final contentBytes =
      4 + 32 + 4 + 4 + numParts * 4 + totalPoints * 16; // type+bbox+np+npts+parts+points
  final totalBytes = 100 + 8 + contentBytes;
  final bytes = Uint8List(totalBytes);
  final data = ByteData.sublistView(bytes);

  // File header
  data.setInt32(0, 9994, Endian.big);
  data.setInt32(24, totalBytes ~/ 2, Endian.big);
  data.setInt32(28, 1000, Endian.little);
  data.setInt32(32, shapeType, Endian.little);

  // Record header
  data.setInt32(100, 1, Endian.big);
  data.setInt32(104, contentBytes ~/ 2, Endian.big);

  // Content
  var off = 108;
  data.setInt32(off, shapeType, Endian.little);
  off += 4;
  off += 32; // bounding box (zeroed)
  data.setInt32(off, numParts, Endian.little);
  off += 4;
  data.setInt32(off, totalPoints, Endian.little);
  off += 4;

  var partStart = 0;
  for (var i = 0; i < numParts; i++) {
    data.setInt32(off, partStart, Endian.little);
    off += 4;
    partStart += parts[i].length;
  }
  for (final ring in parts) {
    for (final pt in ring) {
      data.setFloat64(off, pt[0], Endian.little);
      off += 8;
      data.setFloat64(off, pt[1], Endian.little);
      off += 8;
    }
  }
  return bytes;
}

void main() {
  const parser = ShpParser();

  final square = [
    [0.0, 0.0],
    [1.0, 0.0],
    [1.0, 1.0],
    [0.0, 1.0],
    [0.0, 0.0],
  ];

  test('parses polygon → ShpPolygon with correct ring coordinates', () {
    final shp = buildPolygonShp([square]);
    final result = parser.parse(shp);
    expect(result, hasLength(1));
    final geom = result.first as ShpPolygon;
    expect(geom.rings, hasLength(1));
    expect(geom.rings.first, hasLength(5));
    expect(geom.rings.first.first[0], closeTo(0.0, 1e-9));
  });

  test('parses polyline → ShpPolyline with correct part coordinates', () {
    final line = [[0.0, 0.0], [1.0, 1.0]];
    final shp = buildPolylineShp([line]);
    final result = parser.parse(shp);
    expect(result, hasLength(1));
    final geom = result.first as ShpPolyline;
    expect(geom.parts, hasLength(1));
    expect(geom.parts.first.last[0], closeTo(1.0, 1e-9));
  });

  test('polygon toGeoJson produces Polygon type', () {
    final shp = buildPolygonShp([square]);
    final geom = parser.parse(shp).first as ShpPolygon;
    final json = geom.toGeoJson();
    expect(json['type'], 'Polygon');
    expect((json['coordinates'] as List).first, hasLength(5));
  });

  test('polyline toGeoJson produces LineString for single part', () {
    final line = [[0.0, 0.0], [1.0, 1.0]];
    final shp = buildPolylineShp([line]);
    final geom = parser.parse(shp).first as ShpPolyline;
    expect(geom.toGeoJson()['type'], 'LineString');
  });

  test('polyline toGeoJson produces MultiLineString for multiple parts', () {
    final line = [[0.0, 0.0], [1.0, 1.0]];
    final shp = buildPolylineShp([line, line]);
    final geom = parser.parse(shp).first as ShpPolyline;
    expect(geom.toGeoJson()['type'], 'MultiLineString');
  });
}
