// lib/core/sync/shapefile/shp_parser.dart
import 'dart:typed_data';

sealed class ShpGeometry {
  const ShpGeometry();
  Map<String, dynamic> toGeoJson();
}

class ShpPolygon extends ShpGeometry {
  const ShpPolygon(this.rings);
  final List<List<List<double>>> rings;

  @override
  Map<String, dynamic> toGeoJson() => {
        'type': 'Polygon',
        'coordinates': rings,
      };
}

class ShpPolyline extends ShpGeometry {
  const ShpPolyline(this.parts);
  final List<List<List<double>>> parts;

  @override
  Map<String, dynamic> toGeoJson() {
    if (parts.length == 1) {
      return {'type': 'LineString', 'coordinates': parts.first};
    }
    return {'type': 'MultiLineString', 'coordinates': parts};
  }
}

class ShpParser {
  const ShpParser();

  List<ShpGeometry> parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final geometries = <ShpGeometry>[];
    var offset = 100; // skip file header

    while (offset + 8 <= bytes.length) {
      final contentWords = data.getInt32(offset + 4, Endian.big);
      final contentBytes = contentWords * 2;
      offset += 8;
      if (offset + contentBytes > bytes.length) break;

      final shapeType = data.getInt32(offset, Endian.little);

      if (shapeType == 5 || shapeType == 15 || shapeType == 25) {
        geometries.add(_parsePolygon(data, offset));
      } else if (shapeType == 3 || shapeType == 13 || shapeType == 23) {
        geometries.add(_parsePolyline(data, offset));
      }

      offset += contentBytes;
    }

    return geometries;
  }

  ShpPolygon _parsePolygon(ByteData data, int offset) {
    final numParts = data.getInt32(offset + 36, Endian.little);
    final numPoints = data.getInt32(offset + 40, Endian.little);
    return ShpPolygon(_readParts(data, offset, numParts, numPoints));
  }

  ShpPolyline _parsePolyline(ByteData data, int offset) {
    final numParts = data.getInt32(offset + 36, Endian.little);
    final numPoints = data.getInt32(offset + 40, Endian.little);
    return ShpPolyline(_readParts(data, offset, numParts, numPoints));
  }

  List<List<List<double>>> _readParts(
    ByteData data,
    int offset,
    int numParts,
    int numPoints,
  ) {
    final partIndices = <int>[];
    for (var i = 0; i < numParts; i++) {
      partIndices.add(data.getInt32(offset + 44 + i * 4, Endian.little));
    }

    final pointsBase = offset + 44 + numParts * 4;
    final allPoints = <List<double>>[];
    for (var i = 0; i < numPoints; i++) {
      final x = data.getFloat64(pointsBase + i * 16, Endian.little);
      final y = data.getFloat64(pointsBase + i * 16 + 8, Endian.little);
      allPoints.add([x, y]);
    }

    final result = <List<List<double>>>[];
    for (var i = 0; i < numParts; i++) {
      final start = partIndices[i];
      final end = i < numParts - 1 ? partIndices[i + 1] : numPoints;
      result.add(allPoints.sublist(start, end));
    }
    return result;
  }
}
