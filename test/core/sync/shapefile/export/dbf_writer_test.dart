// test/core/sync/shapefile/export/dbf_writer_test.dart
import 'dart:convert';

import 'package:firecheck/core/sync/shapefile/dbf_parser.dart';
import 'package:firecheck/core/sync/shapefile/export/dbf_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const writer = DbfWriter();
  const parser = DbfParser();

  final fields = [
    const DbfFieldDef(name: 'FEAT_ID', type: 'C', width: 36),
    const DbfFieldDef(name: 'STOREYS', type: 'N', width: 3),
    const DbfFieldDef(name: 'NOT_EXIST', type: 'L', width: 1),
    const DbfFieldDef(name: 'REMARKS', type: 'C', width: 254),
  ];

  test('round-trip: written DBF parses back with correct field names and types', () {
    final bytes = writer.write(fields, []);
    final result = parser.parse(bytes);

    expect(result.fields, hasLength(4));
    expect(result.fields[0].name, equals('FEAT_ID'));
    expect(result.fields[0].type, equals('C'));
    expect(result.fields[1].name, equals('STOREYS'));
    expect(result.fields[1].type, equals('N'));
    expect(result.fields[2].name, equals('NOT_EXIST'));
    expect(result.fields[2].type, equals('L'));
    expect(result.fields[3].name, equals('REMARKS'));
  });

  test('round-trip: C field value survives write and parse', () {
    final bytes = writer.write(fields, [
      {'FEAT_ID': 'abc-123', 'STOREYS': null, 'NOT_EXIST': null, 'REMARKS': null},
    ]);
    final result = parser.parse(bytes);

    expect(result.records, hasLength(1));
    expect(result.records.first['FEAT_ID'], equals('abc-123'));
  });

  test('round-trip: N field value is right-aligned and parses back trimmed', () {
    final bytes = writer.write(fields, [
      {'FEAT_ID': null, 'STOREYS': '42', 'NOT_EXIST': null, 'REMARKS': null},
    ]);
    final result = parser.parse(bytes);
    expect(result.records.first['STOREYS'], equals('42'));
  });

  test('round-trip: L field T writes as T', () {
    final bytes = writer.write(fields, [
      {'FEAT_ID': null, 'STOREYS': null, 'NOT_EXIST': 'T', 'REMARKS': null},
    ]);
    final result = parser.parse(bytes);
    expect(result.records.first['NOT_EXIST'], equals('T'));
  });

  test('round-trip: L field F writes as F', () {
    final bytes = writer.write(fields, [
      {'FEAT_ID': null, 'STOREYS': null, 'NOT_EXIST': 'F', 'REMARKS': null},
    ]);
    final result = parser.parse(bytes);
    expect(result.records.first['NOT_EXIST'], equals('F'));
  });

  test('null C value writes as blank (empty string after trim)', () {
    final bytes = writer.write(fields, [
      {'FEAT_ID': null, 'STOREYS': null, 'NOT_EXIST': null, 'REMARKS': null},
    ]);
    final result = parser.parse(bytes);
    expect(result.records.first['REMARKS'], isEmpty);
  });

  test('pipe-delimited value survives round-trip intact', () {
    const pipeValue = 'sprinkler|extinguisher|hose';
    final bytes = writer.write(fields, [
      {'FEAT_ID': null, 'STOREYS': null, 'NOT_EXIST': null, 'REMARKS': pipeValue},
    ]);
    final result = parser.parse(bytes);
    expect(result.records.first['REMARKS'], equals(pipeValue));
  });

  test('multiple records all present in output', () {
    final bytes = writer.write(fields, [
      {'FEAT_ID': 'id-1', 'STOREYS': '1', 'NOT_EXIST': 'F', 'REMARKS': null},
      {'FEAT_ID': 'id-2', 'STOREYS': '2', 'NOT_EXIST': 'T', 'REMARKS': 'note'},
    ]);
    final result = parser.parse(bytes);

    expect(result.records, hasLength(2));
    expect(result.records[0]['FEAT_ID'], equals('id-1'));
    expect(result.records[1]['FEAT_ID'], equals('id-2'));
    expect(result.records[1]['NOT_EXIST'], equals('T'));
  });

  test('field names longer than 10 chars trip the assertion (US-40)', () {
    final tooLong = [
      const DbfFieldDef(name: 'TOO_LONG_NAME', type: 'C', width: 10),
    ];
    expect(() => writer.write(tooLong, []), throwsA(isA<AssertionError>()));
  });

  test('multi-byte UTF-8 strings are never split mid-codepoint (US-40)', () {
    // 'á' is 2 UTF-8 bytes (0xC3 0xA1). With width=3, we can fit one 'á'
    // (2 bytes) plus 1 padding byte; the second 'á' must be skipped entirely
    // rather than half-written, which would produce an invalid UTF-8 sequence
    // that QGIS (with .cpg=UTF-8) would surface as warnings.
    final narrow = [const DbfFieldDef(name: 'NAME', type: 'C', width: 3)];
    final bytes = writer.write(narrow, [
      {'NAME': 'áá'},
    ]);
    // Field-data area for a 1-record DBF with one width-3 field lives
    // immediately after the header. Easier to extract via the parser's
    // header-size math, but simpler: scan for the data bytes and assert
    // that the bytes form a valid UTF-8 prefix.
    // Locate the start of the records area: header is 32 + 32*1 + 1 = 65 bytes.
    // Each record is 1 (deletion flag) + 3 (field) = 4 bytes.
    final fieldBytes = bytes.sublist(65 + 1, 65 + 1 + 3);
    // Trim trailing 0x20 (DBF space padding) before validating.
    final end = fieldBytes.lastIndexWhere((b) => b != 0x20) + 1;
    final trimmed = fieldBytes.sublist(0, end);
    // Bytes must be a valid UTF-8 sequence — decode without throwing.
    expect(() => utf8.decode(trimmed), returnsNormally);
    expect(utf8.decode(trimmed), equals('á'));
  });
}
