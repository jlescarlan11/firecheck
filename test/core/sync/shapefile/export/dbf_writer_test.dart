// test/core/sync/shapefile/export/dbf_writer_test.dart
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
}
