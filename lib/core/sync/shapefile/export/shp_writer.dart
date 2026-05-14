// lib/core/sync/shapefile/export/shp_writer.dart
import 'dart:typed_data';

class ShpWriteResult {
  const ShpWriteResult({required this.shp, required this.shx});
  final Uint8List shp;
  final Uint8List shx;
}

class ShpWriter {
  const ShpWriter();

  /// Writes polygon shapefile (shape type 5).
  /// [geometries]: one entry per feature; each entry is a list of rings;
  /// each ring is a list of [longitude, latitude] pairs.
  ShpWriteResult writePolygons(List<List<List<List<double>>>> geometries) =>
      _write(5, geometries);

  /// Writes polyline shapefile (shape type 3).
  /// [geometries]: one entry per feature; each entry is a list of parts;
  /// each part is a list of [longitude, latitude] pairs.
  ShpWriteResult writePolylines(List<List<List<List<double>>>> geometries) =>
      _write(3, geometries);

  ShpWriteResult _write(
    int shapeType,
    List<List<List<List<double>>>> geometries,
  ) {
    final contents =
        geometries.map((parts) => _buildContent(shapeType, parts)).toList();

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final parts in geometries) {
      for (final part in parts) {
        for (final pt in part) {
          if (pt[0] < minX) minX = pt[0];
          if (pt[0] > maxX) maxX = pt[0];
          if (pt[1] < minY) minY = pt[1];
          if (pt[1] > maxY) maxY = pt[1];
        }
      }
    }
    if (geometries.isEmpty) minX = minY = maxX = maxY = 0.0;

    final shpSize =
        100 + contents.fold<int>(0, (acc, c) => acc + 8 + c.lengthInBytes);
    final shxSize = 100 + geometries.length * 8;

    final shpData = ByteData(shpSize);
    final shxData = ByteData(shxSize);

    _writeFileHeader(shpData, shapeType, shpSize, minX, minY, maxX, maxY);
    _writeFileHeader(shxData, shapeType, shxSize, minX, minY, maxX, maxY);

    var shpByteOffset = 100;
    var shxByteOffset = 100;
    var shpWordOffset = 50; // 100 bytes ÷ 2

    for (var i = 0; i < contents.length; i++) {
      final content = contents[i];
      final contentBytes = content.lengthInBytes;
      final contentWords = contentBytes ~/ 2;

      // Write shp record header (big-endian, which is the default)
      shpData
        ..setInt32(shpByteOffset, i + 1)
        ..setInt32(shpByteOffset + 4, contentWords);
      shpByteOffset += 8;

      for (var b = 0; b < contentBytes; b++) {
        shpData.setUint8(shpByteOffset + b, content.getUint8(b));
      }
      shpByteOffset += contentBytes;

      // Write shx record (big-endian, which is the default)
      shxData
        ..setInt32(shxByteOffset, shpWordOffset)
        ..setInt32(shxByteOffset + 4, contentWords);
      shxByteOffset += 8;

      shpWordOffset += 4 + contentWords; // 8-byte record header = 4 words
    }

    return ShpWriteResult(
      shp: shpData.buffer.asUint8List(),
      shx: shxData.buffer.asUint8List(),
    );
  }

  void _writeFileHeader(
    ByteData data,
    int shapeType,
    int fileSizeBytes,
    double minX,
    double minY,
    double maxX,
    double maxY,
  ) {
    // File code and file length are big-endian (default); version and shape
    // type and bounding box values are little-endian per Esri spec.
    data
      ..setInt32(0, 9994)
      ..setInt32(24, fileSizeBytes ~/ 2)
      ..setInt32(28, 1000, Endian.little)
      ..setInt32(32, shapeType, Endian.little)
      ..setFloat64(36, minX, Endian.little)
      ..setFloat64(44, minY, Endian.little)
      ..setFloat64(52, maxX, Endian.little)
      ..setFloat64(60, maxY, Endian.little);
  }

  ByteData _buildContent(int shapeType, List<List<List<double>>> parts) {
    final numParts = parts.length;
    final numPoints = parts.fold<int>(0, (acc, p) => acc + p.length);

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final part in parts) {
      for (final pt in part) {
        if (pt[0] < minX) minX = pt[0];
        if (pt[0] > maxX) maxX = pt[0];
        if (pt[1] < minY) minY = pt[1];
        if (pt[1] > maxY) maxY = pt[1];
      }
    }
    // A feature with no vertices would otherwise write ±infinity into the
    // record bbox, which QGIS rejects as an invalid shapefile.
    if (numPoints == 0) {
      minX = minY = maxX = maxY = 0.0;
    }

    final size = 4 + 32 + 4 + 4 + numParts * 4 + numPoints * 16;
    final d = ByteData(size);
    var o = 0;

    d.setInt32(o, shapeType, Endian.little);
    o += 4;
    d.setFloat64(o, minX, Endian.little);
    o += 8;
    d.setFloat64(o, minY, Endian.little);
    o += 8;
    d.setFloat64(o, maxX, Endian.little);
    o += 8;
    d.setFloat64(o, maxY, Endian.little);
    o += 8;
    d.setInt32(o, numParts, Endian.little);
    o += 4;
    d.setInt32(o, numPoints, Endian.little);
    o += 4;

    var pointIndex = 0;
    for (var i = 0; i < parts.length; i++) {
      d.setInt32(o, pointIndex, Endian.little);
      o += 4;
      pointIndex += parts[i].length;
    }

    for (final part in parts) {
      for (final pt in part) {
        d.setFloat64(o, pt[0], Endian.little);
        o += 8;
        d.setFloat64(o, pt[1], Endian.little);
        o += 8;
      }
    }

    return d;
  }
}
