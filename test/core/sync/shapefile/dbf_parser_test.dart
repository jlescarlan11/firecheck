// test/core/sync/shapefile/dbf_parser_test.dart
import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/dbf_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a minimal dBASE III file with the given fields and records.
Uint8List buildDbf({
  required List<({String name, int length})> fields,
  required List<Map<String, String>> records,
}) {
  final numFields = fields.length;
  final headerSize = 32 + numFields * 32 + 1;
  final recordSize = 1 + fields.fold<int>(0, (s, f) => s + f.length);
  final totalSize = headerSize + records.length * recordSize + 1;

  final bytes = Uint8List(totalSize);
  final data = ByteData.sublistView(bytes);

  bytes[0] = 3; // dBASE III
  data.setInt32(4, records.length, Endian.little);
  data.setInt16(8, headerSize, Endian.little);
  data.setInt16(10, recordSize, Endian.little);

  for (var i = 0; i < fields.length; i++) {
    final off = 32 + i * 32;
    final name = fields[i].name;
    for (var j = 0; j < name.length && j < 11; j++) {
      bytes[off + j] = name.codeUnitAt(j);
    }
    bytes[off + 11] = 0x43; // 'C'
    bytes[off + 16] = fields[i].length;
  }
  bytes[32 + numFields * 32] = 0x0D; // header terminator

  for (var i = 0; i < records.length; i++) {
    var off = headerSize + i * recordSize;
    bytes[off] = 0x20; // active record
    off++;
    for (final field in fields) {
      final val = (records[i][field.name] ?? '').padRight(field.length);
      for (var j = 0; j < field.length; j++) {
        bytes[off + j] = (j < val.length ? val.codeUnitAt(j) : 0x20) as int;
      }
      off += field.length;
    }
  }
  bytes[totalSize - 1] = 0x1A; // EOF
  return bytes;
}

void main() {
  const parser = DbfParser();

  test('parses field names and record values', () {
    final dbf = buildDbf(
      fields: [
        (name: 'feat_id', length: 10),
        (name: 'bldg_use', length: 20),
      ],
      records: [
        {'feat_id': 'BLD-001', 'bldg_use': 'residential'},
      ],
    );
    final result = parser.parse(dbf);
    expect(result.fields, hasLength(2));
    expect(result.fields.first.name, 'feat_id');
    expect(result.records, hasLength(1));
    expect(result.records.first['feat_id'], 'BLD-001');
    expect(result.records.first['bldg_use'], 'residential');
  });

  test('trims whitespace from field values', () {
    final dbf = buildDbf(
      fields: [(name: 'feat_id', length: 10)],
      records: [
        {'feat_id': 'X1'},
      ],
    );
    final result = parser.parse(dbf);
    expect(result.records.first['feat_id'], 'X1');
  });

  test('returns zero records for empty record section', () {
    final dbf = buildDbf(fields: [(name: 'feat_id', length: 10)], records: []);
    expect(parser.parse(dbf).records, isEmpty);
  });
}
