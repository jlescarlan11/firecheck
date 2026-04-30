// test/core/sync/shapefile/shapefile_importer_test.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/sync/shapefile/dbf_parser.dart';
import 'package:firecheck/core/sync/shapefile/reprojector.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_importer.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_validator.dart';
import 'package:flutter_test/flutter_test.dart';

// ── helpers ────────────────────────────────────────────────────────────────

Uint8List _buildDbf({
  required List<({String name, int length})> fields,
  required List<Map<String, String>> records,
}) {
  final numFields = fields.length;
  final headerSize = 32 + numFields * 32 + 1;
  final recordSize = 1 + fields.fold<int>(0, (s, f) => s + f.length);
  final totalSize = headerSize + records.length * recordSize + 1;
  final bytes = Uint8List(totalSize);
  final data = ByteData.sublistView(bytes);
  bytes[0] = 3;
  data.setInt32(4, records.length, Endian.little);
  data.setInt16(8, headerSize, Endian.little);
  data.setInt16(10, recordSize, Endian.little);
  for (var i = 0; i < fields.length; i++) {
    final off = 32 + i * 32;
    final name = fields[i].name;
    for (var j = 0; j < name.length && j < 11; j++) {
      bytes[off + j] = name.codeUnitAt(j);
    }
    bytes[off + 11] = 0x43;
    bytes[off + 16] = fields[i].length;
  }
  bytes[32 + numFields * 32] = 0x0D;
  for (var i = 0; i < records.length; i++) {
    var off = headerSize + i * recordSize;
    bytes[off++] = 0x20;
    for (final f in fields) {
      final val = (records[i][f.name] ?? '').padRight(f.length);
      for (var j = 0; j < f.length; j++) {
        bytes[off + j] = j < val.length ? val.codeUnitAt(j) : 0x20;
      }
      off += f.length;
    }
  }
  bytes[totalSize - 1] = 0x1A;
  return bytes;
}

Uint8List _buildPolygonShp(List<List<List<double>>> rings) {
  final total = rings.fold(0, (s, r) => s + r.length);
  final content = 4 + 32 + 4 + 4 + rings.length * 4 + total * 16;
  final all = 100 + 8 + content;
  final bytes = Uint8List(all);
  final data = ByteData.sublistView(bytes);
  data.setInt32(0, 9994, Endian.big);
  data.setInt32(24, all ~/ 2, Endian.big);
  data.setInt32(28, 1000, Endian.little);
  data.setInt32(32, 5, Endian.little);
  data.setInt32(100, 1, Endian.big);
  data.setInt32(104, content ~/ 2, Endian.big);
  var off = 108;
  data.setInt32(off, 5, Endian.little); off += 4 + 32;
  data.setInt32(off, rings.length, Endian.little); off += 4;
  data.setInt32(off, total, Endian.little); off += 4;
  var ps = 0;
  for (var i = 0; i < rings.length; i++) {
    data.setInt32(off, ps, Endian.little); off += 4; ps += rings[i].length;
  }
  for (final r in rings) {
    for (final p in r) {
      data.setFloat64(off, p[0], Endian.little); off += 8;
      data.setFloat64(off, p[1], Endian.little); off += 8;
    }
  }
  return bytes;
}

Uint8List _buildPolylineShp(List<List<List<double>>> parts) {
  final total = parts.fold(0, (s, r) => s + r.length);
  final content = 4 + 32 + 4 + 4 + parts.length * 4 + total * 16;
  final all = 100 + 8 + content;
  final bytes = Uint8List(all);
  final data = ByteData.sublistView(bytes);
  data.setInt32(0, 9994, Endian.big);
  data.setInt32(24, all ~/ 2, Endian.big);
  data.setInt32(28, 1000, Endian.little);
  data.setInt32(32, 3, Endian.little);
  data.setInt32(100, 1, Endian.big);
  data.setInt32(104, content ~/ 2, Endian.big);
  var off = 108;
  data.setInt32(off, 3, Endian.little); off += 4 + 32;
  data.setInt32(off, parts.length, Endian.little); off += 4;
  data.setInt32(off, total, Endian.little); off += 4;
  var ps = 0;
  for (var i = 0; i < parts.length; i++) {
    data.setInt32(off, ps, Endian.little); off += 4; ps += parts[i].length;
  }
  for (final r in parts) {
    for (final p in r) {
      data.setFloat64(off, p[0], Endian.little); off += 8;
      data.setFloat64(off, p[1], Endian.little); off += 8;
    }
  }
  return bytes;
}

const _prj = 'PROJCS["WGS_1984_UTM_Zone_51N",AUTHORITY["EPSG","32651"]]';

Uint8List _makeValidZip() {
  final arc = Archive();

  final boundaryRing = [
    [500000.0, 1000000.0], [501000.0, 1000000.0],
    [501000.0, 1001000.0], [500000.0, 1001000.0], [500000.0, 1000000.0],
  ];
  arc
    ..addFile(ArchiveFile('boundary.shp', -1, _buildPolygonShp([boundaryRing])))
    ..addFile(ArchiveFile('boundary.dbf', -1,
        _buildDbf(fields: [(name: 'feat_id', length: 10)],
            records: [{'feat_id': 'BOUND-1'}])))
    ..addFile(ArchiveFile('boundary.shx', -1, Uint8List(100)))
    ..addFile(ArchiveFile('boundary.prj', -1, utf8.encode(_prj)));

  final bldgRing = [
    [500100.0, 1000100.0], [500200.0, 1000100.0],
    [500200.0, 1000200.0], [500100.0, 1000200.0], [500100.0, 1000100.0],
  ];
  arc
    ..addFile(ArchiveFile('buildings.shp', -1, _buildPolygonShp([bldgRing])))
    ..addFile(ArchiveFile('buildings.dbf', -1,
        _buildDbf(
          fields: [
            (name: 'feat_id', length: 10),
            (name: 'bldg_use', length: 20),
            (name: 'bldg_type', length: 20),
          ],
          records: [{'feat_id': 'BLD-001', 'bldg_use': 'residential', 'bldg_type': 'house'}],
        )))
    ..addFile(ArchiveFile('buildings.shx', -1, Uint8List(100)))
    ..addFile(ArchiveFile('buildings.prj', -1, utf8.encode(_prj)));

  final roadLine = [[500050.0, 1000050.0], [500150.0, 1000150.0]];
  arc
    ..addFile(ArchiveFile('roads.shp', -1, _buildPolylineShp([roadLine])))
    ..addFile(ArchiveFile('roads.dbf', -1,
        _buildDbf(
          fields: [(name: 'feat_id', length: 10), (name: 'road_type', length: 20)],
          records: [{'feat_id': 'RD-001', 'road_type': 'local'}],
        )))
    ..addFile(ArchiveFile('roads.shx', -1, Uint8List(100)))
    ..addFile(ArchiveFile('roads.prj', -1, utf8.encode(_prj)));

  return Uint8List.fromList(ZipEncoder().encode(arc)!);
}

// ── tests ──────────────────────────────────────────────────────────────────

void main() {
  late AppDatabase db;
  late ShapefileImporter importer;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    importer = ShapefileImporter(
      db: db,
      validator: const ShapefileValidator(),
      dbfParser: const DbfParser(),
      reprojector: Reprojector(),
    );
  });

  tearDown(() => db.close());

  test('valid zip → assignment row + 1 building + 1 road in Drift', () async {
    final result = await importer.importInputZip(
      _makeValidZip(),
      'brgy-001',
      '2026-04-28T10:00:00Z',
      'folder-abc',
      'test-enumerator',
    );

    expect(result.buildingCount, 1);
    expect(result.roadCount, 1);

    final assignment = await (db.select(db.assignments)
          ..where((t) => t.id.equals('brgy-001')))
        .getSingleOrNull();
    expect(assignment, isNotNull);
    expect(assignment!.driveModifiedTime, '2026-04-28T10:00:00Z');
    expect(assignment.driveFolderId, 'folder-abc');

    final features = await (db.select(db.features)
          ..where((t) => t.assignmentId.equals('brgy-001')))
        .get();
    expect(features, hasLength(2));
    expect(features.where((f) => f.featureType == 'building'), hasLength(1));
    expect(features.where((f) => f.featureType == 'road'), hasLength(1));
  });

  test('missing layer → ShapefileValidationFailure, no Drift writes', () async {
    final arc = Archive();
    arc.addFile(ArchiveFile('boundary.shp', -1, Uint8List(0)));
    final zipBytes = Uint8List.fromList(ZipEncoder().encode(arc)!);

    expect(
      () => importer.importInputZip(zipBytes, 'x', 't', 'f', 'e'),
      throwsA(isA<ShapefileValidationFailure>()),
    );

    final rows = await db.select(db.assignments).get();
    expect(rows, isEmpty);
  });

  test('corrupt zip → throws, no Drift writes', () async {
    expect(
      () => importer.importInputZip(Uint8List(10), 'x', 't', 'f', 'e'),
      throwsA(anything),
    );
    expect(await db.select(db.assignments).get(), isEmpty);
  });
}
