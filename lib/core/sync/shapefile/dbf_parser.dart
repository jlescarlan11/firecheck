// lib/core/sync/shapefile/dbf_parser.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

@immutable
class DbfField {
  const DbfField({required this.name, required this.type, required this.length});
  final String name;
  final String type;
  final int length;
}

@immutable
class DbfResult {
  const DbfResult({required this.fields, required this.records});
  final List<DbfField> fields;
  final List<Map<String, String>> records;
}

class DbfParser {
  const DbfParser();

  DbfResult parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final recordCount = data.getInt32(4, Endian.little);
    final headerSize = data.getUint16(8, Endian.little);
    final recordSize = data.getUint16(10, Endian.little);

    final fields = <DbfField>[];
    var offset = 32;
    while (offset < headerSize - 1 && bytes[offset] != 0x0D) {
      final nameBytes = bytes.sublist(offset, offset + 11);
      final nullIdx = nameBytes.indexOf(0);
      final name = String.fromCharCodes(
        nullIdx >= 0 ? nameBytes.sublist(0, nullIdx) : nameBytes,
      );
      final type = String.fromCharCode(bytes[offset + 11]);
      final length = bytes[offset + 16];
      fields.add(DbfField(name: name, type: type, length: length));
      offset += 32;
    }

    final records = <Map<String, String>>[];
    var recordOffset = headerSize;
    for (var i = 0; i < recordCount; i++) {
      if (recordOffset >= bytes.length) break;
      final deletionFlag = bytes[recordOffset];
      if (deletionFlag != 0x2A) {
        var fieldOffset = recordOffset + 1;
        final record = <String, String>{};
        for (final field in fields) {
          final end = (fieldOffset + field.length).clamp(0, bytes.length);
          final raw = String.fromCharCodes(bytes.sublist(fieldOffset, end));
          record[field.name] = raw.trim();
          fieldOffset += field.length;
        }
        records.add(record);
      }
      recordOffset += recordSize;
    }

    return DbfResult(
      fields: List.unmodifiable(fields),
      records: List.unmodifiable(
        records.map((r) => Map<String, String>.unmodifiable(r)).toList(),
      ),
    );
  }
}
