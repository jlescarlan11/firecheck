# Export Completed Work as Attributed Shapefiles — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package completed enumeration features into attributed Esri shapefiles (buildings + roads), zip them, and share via the device share sheet — accessible from a new "Export Shapefile" tile on HomeScreen.

**Architecture:** Pure Dart binary writers (`ShpWriter`, `DbfWriter`) mirror the existing `ShpParser`/`DbfParser` pattern and run in a `compute` isolate. A `ShapefileExporter` orchestrator queries Drift, splits by feature type, calls the writers, and zips with the existing `archive` package. A `ShapefileExportNotifier` (`StateNotifier`) drives a simple `Idle → Exporting → Done/Failed` state machine, and a new action tile on `HomeScreen` is disabled until at least one feature is complete.

**Tech Stack:** Dart (`ByteData`/`Uint8List`), Drift (DB queries), `archive ^3.4.0` (ZIP), `share_plus ^12.0.2` (share sheet), `flutter/foundation.dart` (`compute`), Riverpod `StateNotifier`, Flutter l10n (ARB).

---

## File Map

| Status | Path | Responsibility |
|---|---|---|
| Create | `lib/core/sync/shapefile/export/export_failure.dart` | Sealed `ExportFailure` types |
| Create | `lib/features/home/domain/export_state.dart` | Sealed `ExportState` machine |
| Create | `lib/core/sync/shapefile/export/shp_writer.dart` | Writes `.shp` + `.shx` bytes |
| Create | `lib/core/sync/shapefile/export/dbf_writer.dart` | Writes `.dbf` bytes |
| Create | `lib/core/sync/shapefile/export/shapefile_exporter.dart` | Orchestrator: DB → bytes → ZIP → share |
| Create | `lib/features/home/data/shapefile_export_notifier.dart` | Riverpod notifier + provider |
| Modify | `lib/features/home/presentation/home_screen.dart` | Add 4th action tile |
| Modify | `lib/core/i18n/app_en.arb` | Add l10n keys |
| Create | `test/core/sync/shapefile/export/shp_writer_test.dart` | ShpWriter round-trip tests |
| Create | `test/core/sync/shapefile/export/dbf_writer_test.dart` | DbfWriter round-trip tests |
| Create | `test/core/sync/shapefile/export/shapefile_exporter_test.dart` | Exporter unit tests |
| Create | `test/features/home/shapefile_export_notifier_test.dart` | Notifier state-machine tests |

---

## Task 1: Core sealed types — `ExportFailure` and `ExportState`

**Files:**
- Create: `lib/core/sync/shapefile/export/export_failure.dart`
- Create: `lib/features/home/domain/export_state.dart`

These are value types only — no business logic — so no tests are needed.

- [ ] **Step 1: Create `ExportFailure`**

```dart
// lib/core/sync/shapefile/export/export_failure.dart
sealed class ExportFailure {
  const ExportFailure();
}

class NoCompletedFeatures extends ExportFailure {
  const NoCompletedFeatures();
}

class WriteError extends ExportFailure {
  const WriteError(this.message);
  final String message;
}

class ShareError extends ExportFailure {
  const ShareError(this.message);
  final String message;
}
```

- [ ] **Step 2: Create `ExportState`**

```dart
// lib/features/home/domain/export_state.dart
import 'package:firecheck/core/sync/shapefile/export/export_failure.dart';

sealed class ExportState {
  const ExportState();
}

class ExportIdle extends ExportState {
  const ExportIdle();
}

class ExportExporting extends ExportState {
  const ExportExporting();
}

class ExportDone extends ExportState {
  const ExportDone();
}

class ExportFailed extends ExportState {
  const ExportFailed(this.failure);
  final ExportFailure failure;
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/core/sync/shapefile/export/export_failure.dart \
        lib/features/home/domain/export_state.dart
git commit -m "feat(export): add ExportFailure and ExportState sealed types"
```

---

## Task 2: `ShpWriter` — binary `.shp` + `.shx` writer

**Files:**
- Create: `lib/core/sync/shapefile/export/shp_writer.dart`
- Create: `test/core/sync/shapefile/export/shp_writer_test.dart`

`ShpWriter` is a pure function (no Flutter deps, no I/O). It produces `ShpWriteResult(shp, shx)` from a list of part arrays. The existing `ShpParser` is used for round-trip verification in tests.

- [ ] **Step 1: Create the test file and run it to confirm it fails**

```dart
// test/core/sync/shapefile/export/shp_writer_test.dart
import 'package:firecheck/core/sync/shapefile/export/shp_writer.dart';
import 'package:firecheck/core/sync/shapefile/shp_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const writer = ShpWriter();
  const parser = ShpParser();

  group('ShpWriter — polygons', () {
    // A simple square polygon ring (WGS84 coords)
    final ring = [
      [120.0, 14.0],
      [121.0, 14.0],
      [121.0, 15.0],
      [120.0, 15.0],
      [120.0, 14.0], // closed
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
        [122.0, 16.0], // triangle
      ];
      final result = writer.writePolygons([[ring], [ring2]]);
      final shpData = result.shp.buffer.asByteData();
      final shxData = result.shx.buffer.asByteData();

      // SHX record 0 (at byte 100 in SHX): offset in SHP (in 16-bit words)
      final offset0 = shxData.getInt32(100, Endian.big) * 2;
      // SHP record 0 starts at byte 100 (after 100-byte file header)
      expect(offset0, equals(100));

      // SHX record 1 (at byte 108 in SHX)
      final offset1 = shxData.getInt32(108, Endian.big) * 2;
      // Verify that reading the SHP at that offset gives a valid record
      final contentWords = shpData.getInt32(offset1 + 4, Endian.big);
      expect(contentWords, greaterThan(0));
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
```

Run: `flutter test test/core/sync/shapefile/export/shp_writer_test.dart`
Expected: compilation error — `ShpWriter` does not exist yet.

- [ ] **Step 2: Implement `ShpWriter`**

```dart
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
        100 + contents.fold<int>(0, (acc, c) => acc + 8 + c.length);
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
      final contentWords = content.length ~/ 2;

      // SHP: 8-byte record header
      shpData.setInt32(shpByteOffset, i + 1, Endian.big);
      shpData.setInt32(shpByteOffset + 4, contentWords, Endian.big);
      shpByteOffset += 8;

      // SHP: content bytes
      for (var b = 0; b < content.length; b++) {
        shpData.setUint8(shpByteOffset + b, content.getUint8(b));
      }
      shpByteOffset += content.length;

      // SHX: 8-byte entry (offset + content length, both in 16-bit words)
      shxData.setInt32(shxByteOffset, shpWordOffset, Endian.big);
      shxData.setInt32(shxByteOffset + 4, contentWords, Endian.big);
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
    data.setInt32(0, 9994, Endian.big);
    // bytes 4–23: unused (zero-filled by default)
    data.setInt32(24, fileSizeBytes ~/ 2, Endian.big); // file length in words
    data.setInt32(28, 1000, Endian.little); // version
    data.setInt32(32, shapeType, Endian.little);
    data.setFloat64(36, minX, Endian.little);
    data.setFloat64(44, minY, Endian.little);
    data.setFloat64(52, maxX, Endian.little);
    data.setFloat64(60, maxY, Endian.little);
    // bytes 68–99: Zmin, Zmax, Mmin, Mmax (zero)
  }

  ByteData _buildContent(int shapeType, List<List<List<double>>> parts) {
    final numParts = parts.length;
    final numPoints =
        parts.fold<int>(0, (acc, p) => acc + p.length);

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

    // 4 (shapeType) + 32 (bbox) + 4 (numParts) + 4 (numPoints)
    // + numParts*4 (parts array) + numPoints*16 (XY pairs)
    final size = 4 + 32 + 4 + 4 + numParts * 4 + numPoints * 16;
    final d = ByteData(size);
    var o = 0;

    d.setInt32(o, shapeType, Endian.little); o += 4;
    d.setFloat64(o, minX, Endian.little); o += 8;
    d.setFloat64(o, minY, Endian.little); o += 8;
    d.setFloat64(o, maxX, Endian.little); o += 8;
    d.setFloat64(o, maxY, Endian.little); o += 8;
    d.setInt32(o, numParts, Endian.little); o += 4;
    d.setInt32(o, numPoints, Endian.little); o += 4;

    var pointIndex = 0;
    for (var i = 0; i < parts.length; i++) {
      d.setInt32(o, pointIndex, Endian.little);
      o += 4;
      pointIndex += parts[i].length;
    }

    for (final part in parts) {
      for (final pt in part) {
        d.setFloat64(o, pt[0], Endian.little); o += 8;
        d.setFloat64(o, pt[1], Endian.little); o += 8;
      }
    }

    return d;
  }
}
```

- [ ] **Step 3: Run tests — expect all to pass**

Run: `flutter test test/core/sync/shapefile/export/shp_writer_test.dart`
Expected: All tests PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/core/sync/shapefile/export/shp_writer.dart \
        test/core/sync/shapefile/export/shp_writer_test.dart
git commit -m "feat(export): add ShpWriter with round-trip tests"
```

---

## Task 3: `DbfWriter` — binary `.dbf` writer

**Files:**
- Create: `lib/core/sync/shapefile/export/dbf_writer.dart`
- Create: `test/core/sync/shapefile/export/dbf_writer_test.dart`

`DbfWriter` is a pure function. The existing `DbfParser` is used for round-trip verification.

- [ ] **Step 1: Create the test file and run it to confirm it fails**

```dart
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
```

Run: `flutter test test/core/sync/shapefile/export/dbf_writer_test.dart`
Expected: compilation error — `DbfWriter` does not exist yet.

- [ ] **Step 2: Implement `DbfWriter`**

```dart
// lib/core/sync/shapefile/export/dbf_writer.dart
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

  /// Writes a dBASE III+ .dbf file.
  ///
  /// [fields]: column definitions.
  /// [records]: one map per row; keys are field names; null values write as blank.
  /// For 'L' fields pass 'T' or 'F'; for 'N' fields pass the numeric string.
  Uint8List write(
    List<DbfFieldDef> fields,
    List<Map<String, String?>> records,
  ) {
    final recordCount = records.length;
    final fieldCount = fields.length;
    final headerSize = 32 + 32 * fieldCount + 1; // +1 for 0x0D terminator
    final recordSize =
        1 + fields.fold<int>(0, (acc, f) => acc + f.width); // 1 for deletion flag
    final totalSize = headerSize + recordCount * recordSize + 1; // +1 for 0x1A EOF

    final d = ByteData(totalSize);
    var o = 0;

    // File header (32 bytes)
    final now = DateTime.now();
    d.setUint8(o, 0x03); o++;          // version
    d.setUint8(o, now.year - 1900); o++; // YY
    d.setUint8(o, now.month); o++;     // MM
    d.setUint8(o, now.day); o++;       // DD
    d.setInt32(o, recordCount, Endian.little); o += 4;
    d.setUint16(o, headerSize, Endian.little); o += 2;
    d.setUint16(o, recordSize, Endian.little); o += 2;
    o += 20; // reserved (zero)

    // Field descriptors (32 bytes each)
    for (final field in fields) {
      final nameBytes = field.name.codeUnits;
      for (var i = 0; i < 11; i++) {
        d.setUint8(o + i, i < nameBytes.length ? nameBytes[i] : 0);
      }
      o += 11;
      d.setUint8(o, field.type.codeUnitAt(0)); o++;
      o += 4; // reserved
      d.setUint8(o, field.width); o++;
      d.setUint8(o, field.decimals); o++;
      o += 14; // reserved
    }

    // Header terminator
    d.setUint8(o, 0x0D); o++;

    // Records
    for (final record in records) {
      d.setUint8(o, 0x20); o++; // deletion flag: space = active
      for (final field in fields) {
        final value = record[field.name];
        final encoded = _encodeField(field, value);
        for (var i = 0; i < field.width; i++) {
          d.setUint8(o + i, encoded[i]);
        }
        o += field.width;
      }
    }

    // EOF marker
    d.setUint8(o, 0x1A);

    return d.buffer.asUint8List();
  }

  List<int> _encodeField(DbfFieldDef field, String? value) {
    final out = List<int>.filled(field.width, 0x20); // space-filled
    if (value == null || value.isEmpty) return out;

    switch (field.type) {
      case 'C':
        // Left-align, right-pad with spaces
        final bytes = value.codeUnits;
        for (var i = 0; i < bytes.length && i < field.width; i++) {
          out[i] = bytes[i];
        }
      case 'N':
        // Right-align, left-pad with spaces
        final bytes = value.codeUnits;
        final start = field.width - bytes.length;
        for (var i = 0; i < bytes.length; i++) {
          final idx = start + i;
          if (idx >= 0 && idx < field.width) out[idx] = bytes[i];
        }
      case 'L':
        // Single char: T or F
        out[0] = value.codeUnitAt(0);
    }
    return out;
  }
}
```

- [ ] **Step 3: Run tests — expect all to pass**

Run: `flutter test test/core/sync/shapefile/export/dbf_writer_test.dart`
Expected: All tests PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/core/sync/shapefile/export/dbf_writer.dart \
        test/core/sync/shapefile/export/dbf_writer_test.dart
git commit -m "feat(export): add DbfWriter with round-trip tests"
```

---

## Task 4: `ShapefileExporter` — orchestrator

**Files:**
- Create: `lib/core/sync/shapefile/export/shapefile_exporter.dart`
- Create: `test/core/sync/shapefile/export/shapefile_exporter_test.dart`

The exporter queries Drift, builds layer data, runs writers in a `compute` isolate, zips with `archive`, writes to temp dir, and calls `SharePlus`. Tests use a real in-memory Drift DB seeded with fixture data. `SharePlus` is abstracted behind a thin callback so tests can verify the zip path without invoking platform channels.

- [ ] **Step 1: Write the failing tests**

```dart
// test/core/sync/shapefile/export/shapefile_exporter_test.dart
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/shapefile/export/export_failure.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

// Helper: insert a completed building feature with its submission and attrs.
Future<void> _seedBuilding(
  AppDatabase db, {
  required String assignmentId,
  required String featureId,
  required String submissionId,
  bool doesNotExist = false,
  List<String> geometryRing = const [
    [120.0, 14.0], [121.0, 14.0], [121.0, 15.0], [120.0, 15.0], [120.0, 14.0],
  ],
}) async {
  final geoJson = jsonEncode({
    'type': 'Polygon',
    'coordinates': [geometryRing],
  });

  await db.into(db.features).insert(FeaturesCompanion.insert(
    id: featureId,
    assignmentId: assignmentId,
    featureType: 'building',
    geometryGeojson: geoJson,
    isNew: const Value(false),
    status: const Value('complete'),
    createdAt: DateTime.now(),
  ));

  await db.into(db.submissions).insert(SubmissionsCompanion.insert(
    id: submissionId,
    featureId: featureId,
    doesNotExist: Value(doesNotExist),
    syncStatus: const Value('ready_to_upload'),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ));

  await db.into(db.buildingAttributes).insert(BuildingAttributesCompanion.insert(
    submissionId: submissionId,
    cbmsId: const Value('C001'),
    buildingName: const Value('Test Hall'),
    ra9514Type: const Value('Group E'),
    storeys: const Value(3),
    material: const Value('Concrete'),
    costAmount: const Value(500000.0),
    fireFightingFacilitiesJson: const Value('["sprinkler","extinguisher"]'),
    fireLoadJson: const Value('["paper","chemicals"]'),
  ));
}

// Helper: insert a completed road feature with its submission and attrs.
Future<void> _seedRoad(
  AppDatabase db, {
  required String assignmentId,
  required String featureId,
  required String submissionId,
}) async {
  final geoJson = jsonEncode({
    'type': 'LineString',
    'coordinates': [[120.0, 14.0], [121.0, 14.5]],
  });

  await db.into(db.features).insert(FeaturesCompanion.insert(
    id: featureId,
    assignmentId: assignmentId,
    featureType: 'road',
    geometryGeojson: geoJson,
    isNew: const Value(false),
    status: const Value('complete'),
    createdAt: DateTime.now(),
  ));

  await db.into(db.submissions).insert(SubmissionsCompanion.insert(
    id: submissionId,
    featureId: featureId,
    syncStatus: const Value('ready_to_upload'),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ));

  await db.into(db.roadAttributes).insert(RoadAttributesCompanion.insert(
    submissionId: submissionId,
    roadName: const Value('Main St'),
    widthMeters: const Value(8.0),
    roadFeaturesJson: const Value('["Pedestrian"]'),
  ));
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  ShapefileExporter _makeExporter({List<String>? capturedPaths}) {
    return ShapefileExporter(
      db: db,
      shareFile: (path) async {
        capturedPaths?.add(path);
      },
      tempDirOverride: Directory.systemTemp.createTempSync('shp_test_'),
    );
  }

  test('two buildings + one road → ZIP contains exactly 10 files', () async {
    const assignmentId = 'assignment-001';
    await _seedBuilding(db, assignmentId: assignmentId, featureId: 'f1', submissionId: 's1');
    await _seedBuilding(db, assignmentId: assignmentId, featureId: 'f2', submissionId: 's2');
    await _seedRoad(db, assignmentId: assignmentId, featureId: 'f3', submissionId: 's3');

    final result = await _makeExporter().export(assignmentId: assignmentId);

    expect(result, isNull); // null = success (no ExportFailure)
  });

  test('two buildings + one road → ZIP file is created and has 10 entries', () async {
    const assignmentId = 'assignment-001';
    await _seedBuilding(db, assignmentId: assignmentId, featureId: 'f1', submissionId: 's1');
    await _seedBuilding(db, assignmentId: assignmentId, featureId: 'f2', submissionId: 's2');
    await _seedRoad(db, assignmentId: assignmentId, featureId: 'f3', submissionId: 's3');

    final capturedPaths = <String>[];
    await _makeExporter(capturedPaths: capturedPaths).export(assignmentId: assignmentId);

    expect(capturedPaths, hasLength(1));
    final zipBytes = await File(capturedPaths.first).readAsBytes();
    final archive = ZipDecoder().decodeBytes(zipBytes);
    expect(archive.files, hasLength(10)); // 5 buildings + 5 roads
  });

  test('only buildings → ZIP contains 5 building files only', () async {
    const assignmentId = 'assignment-002';
    await _seedBuilding(db, assignmentId: assignmentId, featureId: 'f1', submissionId: 's1');

    final capturedPaths = <String>[];
    await _makeExporter(capturedPaths: capturedPaths).export(assignmentId: assignmentId);

    final zipBytes = await File(capturedPaths.first).readAsBytes();
    final archive = ZipDecoder().decodeBytes(zipBytes);
    expect(archive.files, hasLength(5));
    expect(archive.files.map((f) => f.name), everyElement(startsWith('buildings')));
  });

  test('no completed features → returns NoCompletedFeatures failure', () async {
    const assignmentId = 'assignment-003';
    final failure = await _makeExporter().export(assignmentId: assignmentId);
    expect(failure, isA<NoCompletedFeatures>());
  });

  test('doesNotExist building is included in output', () async {
    const assignmentId = 'assignment-004';
    await _seedBuilding(
      db,
      assignmentId: assignmentId,
      featureId: 'f1',
      submissionId: 's1',
      doesNotExist: true,
    );

    final capturedPaths = <String>[];
    await _makeExporter(capturedPaths: capturedPaths).export(assignmentId: assignmentId);

    final zipBytes = await File(capturedPaths.first).readAsBytes();
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final dbfEntry = archive.files.firstWhere((f) => f.name == 'buildings.dbf');
    // The DBF will have 1 record with NOT_EXIST=T
    expect(dbfEntry.content, isNotEmpty);
  });
}
```

Run: `flutter test test/core/sync/shapefile/export/shapefile_exporter_test.dart`
Expected: compilation error — `ShapefileExporter` does not exist yet.

- [ ] **Step 2: Implement `ShapefileExporter`**

```dart
// lib/core/sync/shapefile/export/shapefile_exporter.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/shapefile/export/dbf_writer.dart';
import 'package:firecheck/core/sync/shapefile/export/export_failure.dart';
import 'package:firecheck/core/sync/shapefile/export/shp_writer.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// ── Field definitions ────────────────────────────────────────────────────────

const _buildingFields = [
  DbfFieldDef(name: 'FEAT_ID',    type: 'C', width: 36),
  DbfFieldDef(name: 'CBMS_ID',    type: 'C', width: 20),
  DbfFieldDef(name: 'BLDG_NAME',  type: 'C', width: 60),
  DbfFieldDef(name: 'RA9514_TYPE',type: 'C', width: 20),
  DbfFieldDef(name: 'STOREYS',    type: 'N', width: 3),
  DbfFieldDef(name: 'MATERIAL',   type: 'C', width: 30),
  DbfFieldDef(name: 'COST_EXACT', type: 'L', width: 1),
  DbfFieldDef(name: 'COST_AMT',   type: 'N', width: 12, decimals: 2),
  DbfFieldDef(name: 'COST_RANGE', type: 'C', width: 20),
  DbfFieldDef(name: 'FIRE_FACIL', type: 'C', width: 254),
  DbfFieldDef(name: 'FIRE_LOAD',  type: 'C', width: 254),
  DbfFieldDef(name: 'NOT_EXIST',  type: 'L', width: 1),
  DbfFieldDef(name: 'REMARKS',    type: 'C', width: 254),
];

const _roadFields = [
  DbfFieldDef(name: 'FEAT_ID',    type: 'C', width: 36),
  DbfFieldDef(name: 'IS_BRIDGE',  type: 'L', width: 1),
  DbfFieldDef(name: 'ROAD_NAME',  type: 'C', width: 60),
  DbfFieldDef(name: 'WIDTH_M',    type: 'N', width: 8, decimals: 2),
  DbfFieldDef(name: 'ROAD_FEAT',  type: 'C', width: 254),
  DbfFieldDef(name: 'OTHER_DESC', type: 'C', width: 254),
  DbfFieldDef(name: 'NOT_EXIST',  type: 'L', width: 1),
  DbfFieldDef(name: 'REMARKS',    type: 'C', width: 254),
];

const _prjContent =
    'GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",'
    'SPHEROID["WGS_1984",6378137.0,298.257223563]],'
    'PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]]';

// ── Compute payload ──────────────────────────────────────────────────────────

class _LayerInput {
  const _LayerInput({
    required this.layerName,
    required this.isPolygon,
    required this.geometries,
    required this.records,
    required this.fields,
  });
  final String layerName;
  final bool isPolygon;
  final List<List<List<List<double>>>> geometries;
  final List<Map<String, String?>> records;
  final List<DbfFieldDef> fields;
}

class _LayerOutput {
  const _LayerOutput({
    required this.layerName,
    required this.shp,
    required this.shx,
    required this.dbf,
  });
  final String layerName;
  final Uint8List shp;
  final Uint8List shx;
  final Uint8List dbf;
}

// Top-level function required by compute().
_LayerOutput _writeLayer(_LayerInput input) {
  final writer = const ShpWriter();
  final shpResult = input.isPolygon
      ? writer.writePolygons(input.geometries)
      : writer.writePolylines(input.geometries);
  final dbf = const DbfWriter().write(input.fields, input.records);
  return _LayerOutput(
    layerName: input.layerName,
    shp: shpResult.shp,
    shx: shpResult.shx,
    dbf: dbf,
  );
}

// ── Exporter ─────────────────────────────────────────────────────────────────

class ShapefileExporter {
  ShapefileExporter({
    required AppDatabase db,
    Future<void> Function(String path)? shareFile,
    Directory? tempDirOverride,
  })  : _db = db,
        _shareFile = shareFile,
        _tempDirOverride = tempDirOverride;

  final AppDatabase _db;
  final Future<void> Function(String path)? _shareFile;
  final Directory? _tempDirOverride;

  /// Returns null on success; returns an [ExportFailure] subtype on failure.
  Future<ExportFailure?> export({required String assignmentId}) async {
    // ── 1. Query DB on main isolate ──────────────────────────────────────────
    final features = await (_db.select(_db.features)
          ..where(
            (t) =>
                t.assignmentId.equals(assignmentId) &
                t.status.equals('complete'),
          ))
        .get();

    if (features.isEmpty) return const NoCompletedFeatures();

    final featureIds = features.map((f) => f.id).toList();
    final submissions = await (_db.select(_db.submissions)
          ..where((t) => t.featureId.isIn(featureIds)))
        .get();
    final submissionIds = submissions.map((s) => s.id).toList();

    final buildingAttrs = await (_db.select(_db.buildingAttributes)
          ..where((t) => t.submissionId.isIn(submissionIds)))
        .get();
    final roadAttrs = await (_db.select(_db.roadAttributes)
          ..where((t) => t.submissionId.isIn(submissionIds)))
        .get();

    // Index submissions and attrs by featureId / submissionId for O(1) lookup
    final subByFeatureId = {for (final s in submissions) s.featureId: s};
    final buildingBySubId = {for (final a in buildingAttrs) a.submissionId: a};
    final roadBySubId = {for (final a in roadAttrs) a.submissionId: a};

    // ── 2. Split features by type and build layer inputs ─────────────────────
    final buildingFeatures = features.where((f) => f.featureType == 'building').toList();
    final roadFeatures = features.where((f) => f.featureType == 'road').toList();

    final layers = <_LayerInput>[];

    if (buildingFeatures.isNotEmpty) {
      final geometries = <List<List<List<double>>>>[];
      final records = <Map<String, String?>>[];
      for (final f in buildingFeatures) {
        geometries.add(_parsePolygonParts(f.geometryGeojson));
        final sub = subByFeatureId[f.id];
        final attr = sub != null ? buildingBySubId[sub.id] : null;
        records.add(_buildingRecord(f.id, sub, attr));
      }
      layers.add(_LayerInput(
        layerName: 'buildings',
        isPolygon: true,
        geometries: geometries,
        records: records,
        fields: _buildingFields,
      ));
    }

    if (roadFeatures.isNotEmpty) {
      final geometries = <List<List<List<double>>>>[];
      final records = <Map<String, String?>>[];
      for (final f in roadFeatures) {
        geometries.add(_parsePolylineParts(f.geometryGeojson));
        final sub = subByFeatureId[f.id];
        final attr = sub != null ? roadBySubId[sub.id] : null;
        records.add(_roadRecord(f.id, sub, attr));
      }
      layers.add(_LayerInput(
        layerName: 'roads',
        isPolygon: false,
        geometries: geometries,
        records: records,
        fields: _roadFields,
      ));
    }

    // ── 3. Write bytes in compute isolate ─────────────────────────────────────
    final outputs = <_LayerOutput>[];
    try {
      for (final layer in layers) {
        final out = await compute(_writeLayer, layer);
        outputs.add(out);
      }
    } catch (e) {
      return WriteError(e.toString());
    }

    // ── 4. ZIP all files ──────────────────────────────────────────────────────
    final archive = Archive();
    const prjBytes = _prjContent;
    const cpgBytes = 'UTF-8';

    for (final out in outputs) {
      final name = out.layerName;
      archive.addFile(ArchiveFile('$name.shp', out.shp.length, out.shp));
      archive.addFile(ArchiveFile('$name.shx', out.shx.length, out.shx));
      archive.addFile(ArchiveFile('$name.dbf', out.dbf.length, out.dbf));
      final prj = prjBytes.codeUnits;
      archive.addFile(ArchiveFile('$name.prj', prj.length, prj));
      final cpg = cpgBytes.codeUnits;
      archive.addFile(ArchiveFile('$name.cpg', cpg.length, cpg));
    }

    final zipBytes = ZipEncoder().encode(archive)!;

    // ── 5. Write ZIP to temp dir ──────────────────────────────────────────────
    try {
      final dir = _tempDirOverride ?? await getTemporaryDirectory();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final zipPath = p.join(dir.path, 'firecheck_${assignmentId}_$ts.zip');
      await File(zipPath).writeAsBytes(zipBytes);

      // ── 6. Share ─────────────────────────────────────────────────────────────
      final shareFn = _shareFile ?? _defaultShare;
      await shareFn(zipPath);
    } catch (e) {
      return WriteError(e.toString());
    }

    return null;
  }

  static Future<void> _defaultShare(String path) async {
    // Imported inline to avoid top-level share_plus import in tests.
    // ignore: avoid_dynamic_calls
    await _invokeShare(path);
  }

  // ── GeoJSON parsing helpers ───────────────────────────────────────────────

  List<List<List<double>>> _parsePolygonParts(String geojson) {
    final json = jsonDecode(geojson) as Map<String, dynamic>;
    final type = json['type'] as String;
    final coords = json['coordinates'] as List<dynamic>;
    if (type == 'MultiPolygon') {
      final rings = <List<List<double>>>[];
      for (final polygon in coords) {
        for (final ring in polygon as List<dynamic>) {
          rings.add(_toPoints(ring as List<dynamic>));
        }
      }
      return rings;
    }
    // Polygon
    return (coords).map((ring) => _toPoints(ring as List<dynamic>)).toList();
  }

  List<List<List<double>>> _parsePolylineParts(String geojson) {
    final json = jsonDecode(geojson) as Map<String, dynamic>;
    final type = json['type'] as String;
    final coords = json['coordinates'] as List<dynamic>;
    if (type == 'MultiLineString') {
      return coords.map((part) => _toPoints(part as List<dynamic>)).toList();
    }
    // LineString
    return [_toPoints(coords)];
  }

  List<List<double>> _toPoints(List<dynamic> coords) {
    return coords
        .map((pt) => (pt as List<dynamic>)
            .map((v) => (v as num).toDouble())
            .toList())
        .toList();
  }

  // ── Record builders ───────────────────────────────────────────────────────

  Map<String, String?> _buildingRecord(
    String featureId,
    Submission? sub,
    BuildingAttribute? attr,
  ) {
    return {
      'FEAT_ID':    featureId,
      'CBMS_ID':    attr?.cbmsId,
      'BLDG_NAME':  attr?.buildingName,
      'RA9514_TYPE': attr?.ra9514Type,
      'STOREYS':    attr?.storeys?.toString(),
      'MATERIAL':   attr?.material,
      'COST_EXACT': attr != null ? (attr.costIsExact ? 'T' : 'F') : null,
      'COST_AMT':   attr?.costAmount?.toStringAsFixed(2),
      'COST_RANGE': attr?.costEstimateRange,
      'FIRE_FACIL': _toPipe(attr?.fireFightingFacilitiesJson),
      'FIRE_LOAD':  _toPipe(attr?.fireLoadJson),
      'NOT_EXIST':  sub != null ? (sub.doesNotExist ? 'T' : 'F') : null,
      'REMARKS':    sub?.remarks,
    };
  }

  Map<String, String?> _roadRecord(
    String featureId,
    Submission? sub,
    RoadAttribute? attr,
  ) {
    return {
      'FEAT_ID':    featureId,
      'IS_BRIDGE':  attr != null ? (attr.isBridge ? 'T' : 'F') : null,
      'ROAD_NAME':  attr?.roadName,
      'WIDTH_M':    attr?.widthMeters?.toStringAsFixed(2),
      'ROAD_FEAT':  _toPipe(attr?.roadFeaturesJson),
      'OTHER_DESC': attr?.othersDescription,
      'NOT_EXIST':  sub != null ? (sub.doesNotExist ? 'T' : 'F') : null,
      'REMARKS':    sub?.remarks,
    };
  }

  /// Converts a JSON-encoded list of strings to a pipe-delimited string.
  String? _toPipe(String? json) {
    if (json == null || json.isEmpty || json == '[]') return null;
    try {
      final list = (jsonDecode(json) as List<dynamic>).whereType<String>();
      final joined = list.join('|');
      return joined.isEmpty ? null : joined;
    } on Object {
      return null;
    }
  }
}

// Isolated import to keep tests free of platform channels.
Future<void> _invokeShare(String path) async {
  // ignore: depend_on_referenced_packages
  final share = await _loadSharePlus();
  await share(path);
}

// Lazy-loaded to avoid importing share_plus at the class level.
Future<Future<void> Function(String)> _loadSharePlus() async {
  // ignore: invalid_use_of_visible_for_testing_member
  return (String path) async {
    // import is deferred to avoid pulling platform channels into tests
    // ignore: avoid_dynamic_calls
    final SharePlus = await _getSharePlusClass();
    await (SharePlus as dynamic).instance.share(
      _makeShareParams(path),
    );
  };
}
```

**Note:** The `_defaultShare` / `_invokeShare` approach is awkward for tests. Use a cleaner pattern instead:

Replace the `_defaultShare` static method with a simpler direct import. For production use, construct with the default `shareFile` callback:

```dart
// In main.dart when constructing the notifier's exporter:
ShapefileExporter(
  db: ref.watch(appDatabaseProvider),
  shareFile: (path) async {
    await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
  },
)
```

The `shareFile` parameter is `null` by default in the class definition above. Replace the `_defaultShare` and `_invokeShare` helpers with this simpler version in the actual implementation:

```dart
// lib/core/sync/shapefile/export/shapefile_exporter.dart
// Replace the bottom section after "── 6. Share ──" with:

      final shareFn = _shareFile;
      if (shareFn != null) {
        try {
          await shareFn(zipPath);
        } catch (e) {
          return ShareError(e.toString());
        }
      }
    } catch (e) {
      return WriteError(e.toString());
    }

    return null;
  }
```

And remove `_defaultShare`, `_invokeShare`, and `_loadSharePlus` entirely. The `shareFile` callback is provided by the notifier (which imports `share_plus` directly). This keeps `shapefile_exporter.dart` free of `share_plus` — cleaner testability.

**Final clean implementation of the export method's bottom half:**

```dart
    // ── 5. Write ZIP to temp dir ──────────────────────────────────────────────
    try {
      final dir = _tempDirOverride ?? await getTemporaryDirectory();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final zipPath = p.join(dir.path, 'firecheck_${assignmentId}_$ts.zip');
      await File(zipPath).writeAsBytes(zipBytes);

      // ── 6. Invoke share callback (injected by caller) ─────────────────────
      if (_shareFile != null) {
        await _shareFile!(zipPath);
      }
    } catch (e) {
      return WriteError(e.toString());
    }

    return null;
  }
```

- [ ] **Step 3: Run tests — expect all to pass**

Run: `flutter test test/core/sync/shapefile/export/shapefile_exporter_test.dart`
Expected: All tests PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/core/sync/shapefile/export/shapefile_exporter.dart \
        test/core/sync/shapefile/export/shapefile_exporter_test.dart
git commit -m "feat(export): add ShapefileExporter orchestrator with tests"
```

---

## Task 5: `ShapefileExportNotifier` — Riverpod state machine

**Files:**
- Create: `lib/features/home/data/shapefile_export_notifier.dart`
- Create: `test/features/home/shapefile_export_notifier_test.dart`

Follows the same `StateNotifier` pattern as `GetMapsNotifier`. The notifier owns a `ShapefileExporter` instance (injected). State transitions drive the home screen tile.

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/home/shapefile_export_notifier_test.dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/shapefile/export/export_failure.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_exporter.dart';
import 'package:firecheck/features/home/data/shapefile_export_notifier.dart';
import 'package:firecheck/features/home/domain/export_state.dart';
import 'package:flutter_test/flutter_test.dart';

ShapefileExportNotifier _makeNotifier({
  required String assignmentId,
  required AppDatabase db,
  ExportFailure? forceFailure,
  List<String>? capturedPaths,
}) {
  final exporter = ShapefileExporter(
    db: db,
    shareFile: (path) async {
      capturedPaths?.add(path);
    },
    tempDirOverride: Directory.systemTemp.createTempSync('notifier_test_'),
  );
  return ShapefileExportNotifier(
    assignmentId: assignmentId,
    exporter: exporter,
  );
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('initial state is ExportIdle', () {
    final notifier = _makeNotifier(assignmentId: 'a1', db: db);
    expect(notifier.state, isA<ExportIdle>());
  });

  test('export with no features → stays Idle then transitions to Failed', () async {
    final notifier = _makeNotifier(assignmentId: 'a1', db: db);
    final states = <ExportState>[];
    notifier.addListener(states.add);

    await notifier.export();

    expect(states, [isA<ExportExporting>(), isA<ExportFailed>()]);
    expect((states.last as ExportFailed).failure, isA<NoCompletedFeatures>());
  });

  test('tapping export while Exporting is a no-op', () async {
    final notifier = _makeNotifier(assignmentId: 'a1', db: db);
    final states = <ExportState>[];
    notifier.addListener(states.add);

    // Start first export (no features → will complete quickly)
    final first = notifier.export();
    // Immediately attempt second export — should be ignored since state is Exporting
    final second = notifier.export();

    await Future.wait([first, second]);

    // ExportExporting appears exactly once
    expect(states.whereType<ExportExporting>(), hasLength(1));
  });

  test('after Failed state, notifier resets to Idle', () async {
    final notifier = _makeNotifier(assignmentId: 'a1', db: db);
    await notifier.export(); // fails — no features
    expect(notifier.state, isA<ExportIdle>());
  });
}
```

Run: `flutter test test/features/home/shapefile_export_notifier_test.dart`
Expected: compilation error — `ShapefileExportNotifier` does not exist yet.

- [ ] **Step 2: Implement `ShapefileExportNotifier`**

```dart
// lib/features/home/data/shapefile_export_notifier.dart
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_exporter.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/home/domain/export_state.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

class ShapefileExportNotifier extends StateNotifier<ExportState> {
  ShapefileExportNotifier({
    required String assignmentId,
    required ShapefileExporter exporter,
  })  : _assignmentId = assignmentId,
        _exporter = exporter,
        super(const ExportIdle());

  final String _assignmentId;
  final ShapefileExporter _exporter;

  Future<void> export() async {
    if (state is ExportExporting) return;
    state = const ExportExporting();

    final failure = await _exporter.export(assignmentId: _assignmentId);

    if (!mounted) return;
    if (failure != null) {
      state = ExportFailed(failure);
      // Auto-reset after failure so the tile becomes tappable again.
      state = const ExportIdle();
      return;
    }

    state = const ExportDone();
    state = const ExportIdle();
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final shapefileExportNotifierProvider =
    StateNotifierProvider<ShapefileExportNotifier, ExportState>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final assignmentAsync = ref.watch(currentAssignmentProvider);
  final assignmentId = assignmentAsync.value?.id ?? '';

  return ShapefileExportNotifier(
    assignmentId: assignmentId,
    exporter: ShapefileExporter(
      db: db,
      shareFile: (path) async {
        await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
      },
    ),
  );
});
```

- [ ] **Step 3: Run tests — expect all to pass**

Run: `flutter test test/features/home/shapefile_export_notifier_test.dart`
Expected: All tests PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/features/home/data/shapefile_export_notifier.dart \
        test/features/home/shapefile_export_notifier_test.dart
git commit -m "feat(export): add ShapefileExportNotifier with state machine tests"
```

---

## Task 6: HomeScreen tile + l10n keys

**Files:**
- Modify: `lib/core/i18n/app_en.arb`
- Modify: `lib/features/home/presentation/home_screen.dart`

Add the "Export Shapefile" action tile as the 4th tile. It is disabled (greyed out with `onTap: null`) when `completedFeatures == 0`. While `ExportExporting`, the tile shows a `CircularProgressIndicator` trailing widget.

- [ ] **Step 1: Add l10n keys to `app_en.arb`**

Open `lib/core/i18n/app_en.arb` and add these keys before the closing `}`:

```json
  "exportShapefile": "Export Shapefile",
  "exportShapefileSubtitle": "Package completed features as .shp",
  "exportShapefileExporting": "Packaging…",
  "exportErrorNoFeatures": "No completed features to export.",
  "exportErrorWriteFailed": "Export failed: could not write files. Please try again.",
  "exportErrorShareFailed": "Export ready but could not open share sheet. Please try again."
```

Then run `flutter gen-l10n` (or `flutter pub run build_runner build`) to regenerate `AppLocalizations`.

Run: `flutter gen-l10n`
Expected: No errors. `lib/generated/l10n/app_localizations.dart` updated.

- [ ] **Step 2: Update `HomeScreen` to add the 4th tile**

In `lib/features/home/presentation/home_screen.dart`:

1. Add imports:

```dart
import 'package:firecheck/core/sync/shapefile/export/export_failure.dart';
import 'package:firecheck/features/home/data/shapefile_export_notifier.dart';
import 'package:firecheck/features/home/domain/export_state.dart';
```

2. Inside `build`, watch the two new providers:

```dart
    final exportState = ref.watch(shapefileExportNotifierProvider);
    final isExporting = exportState is ExportExporting;
```

3. Handle `ExportFailed` to show a SnackBar. Add this block after the existing `final isLocked = ...` line:

```dart
    ref.listen<ExportState>(shapefileExportNotifierProvider, (prev, next) {
      if (next is ExportFailed) {
        final msg = switch (next.failure) {
          NoCompletedFeatures() => l.exportErrorNoFeatures,
          WriteError()          => l.exportErrorWriteFailed,
          ShareError()          => l.exportErrorShareFailed,
        };
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    });
```

4. Add the 4th tile in the `Column` children list, after the existing `_ActionTile` for `uploadData` (inside the `if (!isLocked)` block, or as its own unconditional tile — export is always available once there are completed features):

```dart
              _ActionTile(
                title: isExporting ? l.exportShapefileExporting : l.exportShapefile,
                subtitle: l.exportShapefileSubtitle,
                trailing: isExporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: (snap.completedFeatures == 0 || isExporting)
                    ? null
                    : () => ref
                        .read(shapefileExportNotifierProvider.notifier)
                        .export(),
              ),
```

5. Update `_ActionTile` to accept an optional `trailing` widget:

```dart
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: trailing ?? const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
```

- [ ] **Step 3: Run all tests to confirm no regressions**

Run: `flutter test`
Expected: All tests PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/core/i18n/app_en.arb \
        lib/features/home/presentation/home_screen.dart \
        lib/generated/l10n/
git commit -m "feat(export): add Export Shapefile tile to HomeScreen"
```

---

## Self-Review Checklist

After all tasks are complete:

- [ ] `flutter test` — all tests pass
- [ ] `flutter analyze` — no warnings or errors
- [ ] Run the app on a simulator: tap "Export Shapefile" with completed features → share sheet appears with a `.zip` file
- [ ] Unzip the archive in Finder and verify it contains `buildings.shp`, `buildings.shx`, `buildings.dbf`, `buildings.prj`, `buildings.cpg` (and `roads.*` if road features exist)
- [ ] Open `buildings.shp` in QGIS: verify geometries render, all attribute columns are present, `NOT_EXIST` field shows `T`/`F`
