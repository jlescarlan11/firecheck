// lib/core/sync/shapefile/export/dbf_writer.dart
import 'dart:convert';
import 'dart:typed_data';

class DbfFieldDef {
  const DbfFieldDef({
    required this.name,
    required this.type,
    required this.width,
    this.decimals = 0,
  });
  final String name;    // max 10 chars, ASCII
  final String type;    // 'C', 'N', or 'L'
  final int width;
  final int decimals;
}

class DbfWriter {
  const DbfWriter();

  Uint8List write(
    List<DbfFieldDef> fields,
    List<Map<String, String?>> records,
  ) {
    for (final f in fields) {
      // DBF field-name area is 11 bytes including the trailing NUL — names
      // longer than 10 chars get silently truncated by readers (e.g. QGIS).
      assert(f.name.length <= 10, 'DBF field name "${f.name}" exceeds 10 chars');
    }
    final recordCount = records.length;
    final fieldCount = fields.length;
    final headerSize = 32 + 32 * fieldCount + 1;
    final recordSize = 1 + fields.fold<int>(0, (acc, f) => acc + f.width);
    final totalSize = headerSize + recordCount * recordSize + 1;

    final d = ByteData(totalSize);
    var o = 0;

    final now = DateTime.now();
    d.setUint8(o, 0x03); o++;
    d.setUint8(o, now.year - 1900); o++;
    d.setUint8(o, now.month); o++;
    d.setUint8(o, now.day); o++;
    d.setInt32(o, recordCount, Endian.little); o += 4;
    d.setUint16(o, headerSize, Endian.little); o += 2;
    d.setUint16(o, recordSize, Endian.little); o += 2;
    o += 20;

    for (final field in fields) {
      final nameBytes = field.name.codeUnits;
      for (var i = 0; i < 11; i++) {
        d.setUint8(o + i, i < nameBytes.length ? nameBytes[i] : 0);
      }
      o += 11;
      d.setUint8(o, field.type.codeUnitAt(0)); o++;
      o += 4;
      d.setUint8(o, field.width); o++;
      d.setUint8(o, field.decimals); o++;
      o += 14;
    }

    d.setUint8(o, 0x0D); o++;

    for (final record in records) {
      d.setUint8(o, 0x20); o++;
      for (final field in fields) {
        final value = record[field.name];
        final encoded = _encodeField(field, value);
        for (var i = 0; i < field.width; i++) {
          d.setUint8(o + i, encoded[i]);
        }
        o += field.width;
      }
    }

    d.setUint8(o, 0x1A);

    return d.buffer.asUint8List();
  }

  List<int> _encodeField(DbfFieldDef field, String? value) {
    final out = List<int>.filled(field.width, 0x20);
    if (value == null || value.isEmpty) return out;

    switch (field.type) {
      case 'C':
        // Encode codepoint-by-codepoint so a multi-byte char that wouldn't
        // fit is skipped entirely — never split mid-codepoint, which would
        // make the .dbf invalid UTF-8 even with a UTF-8 .cpg sidecar.
        var written = 0;
        for (final rune in value.runes) {
          final charBytes = utf8.encode(String.fromCharCode(rune));
          if (written + charBytes.length > field.width) break;
          for (var i = 0; i < charBytes.length; i++) {
            out[written + i] = charBytes[i];
          }
          written += charBytes.length;
        }
      case 'N':
        final bytes = utf8.encode(value);
        final start = field.width - bytes.length;
        for (var i = 0; i < bytes.length; i++) {
          final idx = start + i;
          if (idx >= 0 && idx < field.width) out[idx] = bytes[i];
        }
      case 'L':
        out[0] = value.codeUnitAt(0);
    }
    return out;
  }
}
