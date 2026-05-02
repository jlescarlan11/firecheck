# Shapefile Integrity Validation at Download Time — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand shapefile validation into a 7-rule pipeline that fires after download, adds a soft-warning path, a retry path for transient failures, and fire-and-forget Supabase logging so supervisors can identify broken source files.

**Architecture:** A `ShapefileValidationRule` interface with 7 concrete rule classes is orchestrated by a refactored `ShapefileValidator` returning `ValidationReport` (not throwing). Validation moves from `ShapefileImporter` into `GetMapsNotifier`, adding two new states (`ValidatingShapefiles`, `ShapefileWarning`) and two new methods (`acknowledgeWarning`, `retryDownload`). A `ValidationFailureReporter` writes failures to Supabase fire-and-forget.

**Tech Stack:** Flutter/Dart, Riverpod, Drift, Supabase, googleapis (Drive v3), `crypto` (MD5)

---

## File Map

### New files
| Path | Responsibility |
|------|---------------|
| `lib/core/sync/shapefile/validation/shapefile_validation_rule.dart` | `RuleOutcome` sealed class + `ShapefileValidationRule` interface |
| `lib/core/sync/shapefile/validation/validation_report.dart` | `ValidationReport(fatal, warnings)` value type |
| `lib/core/sync/shapefile/validation/rules/r1_checksum_rule.dart` | MD5 match against Drive metadata |
| `lib/core/sync/shapefile/validation/rules/r2_file_set_rule.dart` | Required files present + size warning |
| `lib/core/sync/shapefile/validation/rules/r3_header_integrity_rule.dart` | .shp file code 9994 + length match |
| `lib/core/sync/shapefile/validation/rules/r4_index_consistency_rule.dart` | .shx ↔ .shp record count + offset bounds |
| `lib/core/sync/shapefile/validation/rules/r5_attribute_integrity_rule.dart` | .dbf parseable + count match + required columns |
| `lib/core/sync/shapefile/validation/rules/r6_geometry_sanity_rule.dart` | ≥1 feature + non-degenerate bbox |
| `lib/core/sync/shapefile/validation/rules/r7_projection_rule.dart` | .prj present (warn if not) and CRS = 32651 |
| `lib/core/validation/validation_failure_reporter.dart` | `ValidationFailureReporter` abstract + `FakeValidationFailureReporter` |
| `lib/core/validation/supabase_validation_failure_reporter.dart` | Supabase `validation_failures` insert |

### Modified files
| Path | Change |
|------|--------|
| `pubspec.yaml` | Add `crypto: ^3.0.0` |
| `lib/core/drive/drive_download_event.dart` | Add `expectedMd5s` to `DriveDownloadComplete` |
| `lib/core/drive/google_drive_api.dart` | Populate `expectedMd5s` from Drive file metadata |
| `lib/core/drive/fake_drive_api.dart` | Pass `expectedMd5s` to `DriveDownloadComplete` |
| `lib/core/errors/failure.dart` | Add `ruleName` to `ShapefileValidationFailure` |
| `lib/core/sync/shapefile/shapefile_validator.dart` | Rewrite as rule orchestrator returning `ValidationReport` |
| `lib/core/sync/shapefile/shapefile_importer.dart` | Remove `validator` field; call `dbfParser.parse()` directly |
| `lib/features/assignment/domain/get_maps_state.dart` | Add `ValidatingShapefiles`, `ShapefileWarning`; add `isRetryable` to `GetMapsError` |
| `lib/features/assignment/presentation/assignment_providers.dart` | Add validator/reporter providers; update notifier |
| `lib/features/assignment/presentation/get_maps_screen.dart` | Handle new states; update error view |
| `lib/core/i18n/app_en.arb` | Add 14 new l10n keys |
| `lib/main.dart` | Wire `validationFailureReporterProvider`; remove validator from importer override |

### Test files
| Path | What it tests |
|------|--------------|
| `test/core/sync/shapefile/validation/rules/r1_checksum_rule_test.dart` | R1 |
| `test/core/sync/shapefile/validation/rules/r2_file_set_rule_test.dart` | R2 |
| `test/core/sync/shapefile/validation/rules/r3_header_integrity_rule_test.dart` | R3 |
| `test/core/sync/shapefile/validation/rules/r4_index_consistency_rule_test.dart` | R4 |
| `test/core/sync/shapefile/validation/rules/r5_attribute_integrity_rule_test.dart` | R5 |
| `test/core/sync/shapefile/validation/rules/r6_geometry_sanity_rule_test.dart` | R6 |
| `test/core/sync/shapefile/validation/rules/r7_projection_rule_test.dart` | R7 |
| `test/core/sync/shapefile/validation/shapefile_validator_test.dart` | Orchestrator |
| `test/features/assignment/get_maps_notifier_test.dart` | New cases appended |

---

## Task 1: Add crypto package and create validation foundation types

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/core/sync/shapefile/validation/shapefile_validation_rule.dart`
- Create: `lib/core/sync/shapefile/validation/validation_report.dart`

- [ ] **Step 1: Add `crypto` to pubspec.yaml**

In `pubspec.yaml`, under `dependencies:`, add after the existing entries:
```yaml
  crypto: ^3.0.0
```

- [ ] **Step 2: Run pub get**

```bash
flutter pub get
```
Expected: resolves without errors.

- [ ] **Step 3: Create rule interface + outcome types**

Create `lib/core/sync/shapefile/validation/shapefile_validation_rule.dart`:
```dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

sealed class RuleOutcome {
  const RuleOutcome();
}

@immutable
class RulePassed extends RuleOutcome {
  const RulePassed();
}

@immutable
class RuleFatal extends RuleOutcome {
  const RuleFatal({required this.ruleName, required this.userMessage});
  // ruleName goes to Supabase log — never displayed to the enumerator
  final String ruleName;
  // userMessage is the plain-English string shown in the error view
  final String userMessage;
}

@immutable
class RuleWarning extends RuleOutcome {
  const RuleWarning({required this.userMessage});
  final String userMessage;
}

abstract class ShapefileValidationRule {
  const ShapefileValidationRule();
  RuleOutcome check(
    Map<String, Uint8List> files,
    Map<String, String> expectedMd5s,
  );
}
```

- [ ] **Step 4: Create ValidationReport**

Create `lib/core/sync/shapefile/validation/validation_report.dart`:
```dart
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter/foundation.dart';

@immutable
class ValidationReport {
  const ValidationReport({this.fatal, this.warnings = const []});

  final RuleFatal? fatal;
  final List<RuleWarning> warnings;

  bool get hasFatals => fatal != null;
  bool get hasWarnings => warnings.isNotEmpty;
  bool get isClean => !hasFatals && !hasWarnings;
}
```

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock \
  lib/core/sync/shapefile/validation/shapefile_validation_rule.dart \
  lib/core/sync/shapefile/validation/validation_report.dart
git commit -m "feat(validation): add crypto package + RuleOutcome types + ValidationReport"
```

---

## Task 2: R1 — Checksum rule (TDD)

**Files:**
- Create: `lib/core/sync/shapefile/validation/rules/r1_checksum_rule.dart`
- Create: `test/core/sync/shapefile/validation/rules/r1_checksum_rule_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/sync/shapefile/validation/rules/r1_checksum_rule_test.dart`:
```dart
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:firecheck/core/sync/shapefile/validation/rules/r1_checksum_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const rule = ChecksumRule();
  final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
  final correctMd5 = md5.convert(bytes).toString();

  test('RulePassed when MD5 matches', () {
    final outcome = rule.check({'boundary.shp': bytes}, {'boundary.shp': correctMd5});
    expect(outcome, isA<RulePassed>());
  });

  test('RuleFatal with ruleName checksum when MD5 mismatches', () {
    final corrupted = Uint8List.fromList([...bytes]..[0] ^= 0xFF);
    final outcome = rule.check({'boundary.shp': corrupted}, {'boundary.shp': correctMd5});
    expect(outcome, isA<RuleFatal>());
    expect((outcome as RuleFatal).ruleName, 'checksum');
  });

  test('RulePassed when file not in expectedMd5s (presence checked by R2)', () {
    final outcome = rule.check({'boundary.shp': bytes}, {});
    expect(outcome, isA<RulePassed>());
  });

  test('RuleFatal for second file if first passes but second mismatches', () {
    final corrupted = Uint8List.fromList([...bytes]..[0] ^= 0xFF);
    final outcome = rule.check(
      {'boundary.shp': bytes, 'buildings.shp': corrupted},
      {'boundary.shp': correctMd5, 'buildings.shp': correctMd5},
    );
    expect(outcome, isA<RuleFatal>());
  });
}
```

- [ ] **Step 2: Run test — expect failure**

```bash
flutter test test/core/sync/shapefile/validation/rules/r1_checksum_rule_test.dart
```
Expected: compile error — `ChecksumRule` not found.

- [ ] **Step 3: Implement R1**

Create `lib/core/sync/shapefile/validation/rules/r1_checksum_rule.dart`:
```dart
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter/foundation.dart';

@immutable
class ChecksumRule extends ShapefileValidationRule {
  const ChecksumRule();

  @override
  RuleOutcome check(
    Map<String, Uint8List> files,
    Map<String, String> expectedMd5s,
  ) {
    for (final entry in expectedMd5s.entries) {
      final bytes = files[entry.key];
      if (bytes == null) continue; // missing files are caught by R2
      final computed = md5.convert(bytes).toString();
      if (computed != entry.value) {
        return const RuleFatal(
          ruleName: 'checksum',
          userMessage: 'The map file was damaged during download.',
        );
      }
    }
    return const RulePassed();
  }
}
```

- [ ] **Step 4: Run test — expect pass**

```bash
flutter test test/core/sync/shapefile/validation/rules/r1_checksum_rule_test.dart
```
Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/shapefile/validation/rules/r1_checksum_rule.dart \
  test/core/sync/shapefile/validation/rules/r1_checksum_rule_test.dart
git commit -m "feat(validation): R1 checksum rule"
```

---

## Task 3: R2 — File-set completeness rule (TDD)

**Files:**
- Create: `lib/core/sync/shapefile/validation/rules/r2_file_set_rule.dart`
- Create: `test/core/sync/shapefile/validation/rules/r2_file_set_rule_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/sync/shapefile/validation/rules/r2_file_set_rule_test.dart`:
```dart
import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/rules/r2_file_set_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Uint8List> _fullFiles() {
  final b = Uint8List.fromList([1]);
  return {
    for (final layer in ['boundary', 'buildings', 'roads'])
      for (final ext in ['.shp', '.dbf', '.shx', '.prj'])
        '$layer$ext': b,
  };
}

void main() {
  const rule = FileSetRule();

  test('RulePassed when all 12 required files present and non-empty', () {
    expect(rule.check(_fullFiles(), {}), isA<RulePassed>());
  });

  test('RuleFatal when a required file is missing', () {
    final files = _fullFiles()..remove('boundary.shp');
    final outcome = rule.check(files, {});
    expect(outcome, isA<RuleFatal>());
    expect((outcome as RuleFatal).ruleName, 'file_set');
  });

  test('RuleFatal when a required file is zero bytes', () {
    final files = _fullFiles()..['buildings.dbf'] = Uint8List(0);
    expect(rule.check(files, {}), isA<RuleFatal>());
  });

  test('RuleWarning when total size exceeds 100 MB', () {
    final files = _fullFiles();
    // Replace one file with 101 MB of bytes to push total over threshold
    files['boundary.shp'] = Uint8List(101 * 1024 * 1024);
    expect(rule.check(files, {}), isA<RuleWarning>());
  });
}
```

- [ ] **Step 2: Run test — expect compile error**

```bash
flutter test test/core/sync/shapefile/validation/rules/r2_file_set_rule_test.dart
```

- [ ] **Step 3: Implement R2**

Create `lib/core/sync/shapefile/validation/rules/r2_file_set_rule.dart`:
```dart
import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter/foundation.dart';

@immutable
class FileSetRule extends ShapefileValidationRule {
  const FileSetRule();

  static const _layers = ['boundary', 'buildings', 'roads'];
  static const _extensions = ['.shp', '.dbf', '.shx', '.prj'];
  static const _largeSizeThreshold = 100 * 1024 * 1024; // 100 MB

  @override
  RuleOutcome check(
    Map<String, Uint8List> files,
    Map<String, String> expectedMd5s,
  ) {
    for (final layer in _layers) {
      for (final ext in _extensions) {
        final key = '$layer$ext';
        final bytes = files[key];
        if (bytes == null || bytes.isEmpty) {
          return RuleFatal(
            ruleName: 'file_set',
            userMessage: 'Map files are missing or incomplete.',
          );
        }
      }
    }

    final totalBytes = files.values.fold(0, (sum, b) => sum + b.length);
    if (totalBytes > _largeSizeThreshold) {
      return const RuleWarning(
        userMessage: 'This assignment is unusually large and may be slow to load.',
      );
    }

    return const RulePassed();
  }
}
```

- [ ] **Step 4: Run test — expect pass**

```bash
flutter test test/core/sync/shapefile/validation/rules/r2_file_set_rule_test.dart
```
Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/shapefile/validation/rules/r2_file_set_rule.dart \
  test/core/sync/shapefile/validation/rules/r2_file_set_rule_test.dart
git commit -m "feat(validation): R2 file-set completeness rule"
```

---

## Task 4: R3 — Header integrity rule (TDD)

**Files:**
- Create: `lib/core/sync/shapefile/validation/rules/r3_header_integrity_rule.dart`
- Create: `test/core/sync/shapefile/validation/rules/r3_header_integrity_rule_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/sync/shapefile/validation/rules/r3_header_integrity_rule_test.dart`:
```dart
import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/rules/r3_header_integrity_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter_test/flutter_test.dart';

// Builds a minimal .shp byte array.
// declaredLengthWords defaults to actualLength / 2 (i.e., correct).
Uint8List _shp({
  int fileCode = 9994,
  int? declaredLengthWords,
  int actualLength = 100,
}) {
  final bytes = Uint8List(actualLength);
  final bd = ByteData.sublistView(bytes);
  bd.setUint32(0, fileCode, Endian.big);
  bd.setUint32(24, declaredLengthWords ?? (actualLength ~/ 2), Endian.big);
  return bytes;
}

Map<String, Uint8List> _filesWithBoundary(Uint8List boundaryShp) => {
      'boundary.shp': boundaryShp,
      'buildings.shp': _shp(),
      'roads.shp': _shp(),
    };

void main() {
  const rule = HeaderIntegrityRule();

  test('RulePassed for valid headers in all three layers', () {
    final files = {
      'boundary.shp': _shp(),
      'buildings.shp': _shp(),
      'roads.shp': _shp(),
    };
    expect(rule.check(files, {}), isA<RulePassed>());
  });

  test('RuleFatal when .shp header is shorter than 100 bytes', () {
    final outcome = rule.check(_filesWithBoundary(Uint8List(50)), {});
    expect(outcome, isA<RuleFatal>());
    expect((outcome as RuleFatal).ruleName, 'header_integrity');
  });

  test('RuleFatal when file code is not 9994', () {
    final outcome = rule.check(_filesWithBoundary(_shp(fileCode: 1234)), {});
    expect(outcome, isA<RuleFatal>());
  });

  test('RuleFatal when declared length * 2 != actual byte length', () {
    // File is 100 bytes but declares 200 bytes (100 words)
    final outcome = rule.check(
      _filesWithBoundary(_shp(declaredLengthWords: 100, actualLength: 100)),
      {},
    );
    expect(outcome, isA<RuleFatal>());
  });

  test('RulePassed when files map has no .shp keys (presence handled by R2)', () {
    expect(rule.check({}, {}), isA<RulePassed>());
  });
}
```

- [ ] **Step 2: Run test — expect compile error**

```bash
flutter test test/core/sync/shapefile/validation/rules/r3_header_integrity_rule_test.dart
```

- [ ] **Step 3: Implement R3**

Create `lib/core/sync/shapefile/validation/rules/r3_header_integrity_rule.dart`:
```dart
import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter/foundation.dart';

@immutable
class HeaderIntegrityRule extends ShapefileValidationRule {
  const HeaderIntegrityRule();

  static const _layers = ['boundary', 'buildings', 'roads'];
  static const _shpFileCode = 9994;

  @override
  RuleOutcome check(
    Map<String, Uint8List> files,
    Map<String, String> expectedMd5s,
  ) {
    for (final layer in _layers) {
      final shp = files['$layer.shp'];
      if (shp == null) continue; // missing files caught by R2

      if (shp.length < 100) {
        return const RuleFatal(
          ruleName: 'header_integrity',
          userMessage: 'Map geometry file is corrupted.',
        );
      }

      final bd = ByteData.sublistView(shp);
      final fileCode = bd.getUint32(0, Endian.big);
      if (fileCode != _shpFileCode) {
        return const RuleFatal(
          ruleName: 'header_integrity',
          userMessage: 'Map geometry file is corrupted.',
        );
      }

      final declaredWords = bd.getUint32(24, Endian.big);
      if (declaredWords * 2 != shp.length) {
        return const RuleFatal(
          ruleName: 'header_integrity',
          userMessage: 'Map geometry file is corrupted.',
        );
      }
    }
    return const RulePassed();
  }
}
```

- [ ] **Step 4: Run test — expect pass**

```bash
flutter test test/core/sync/shapefile/validation/rules/r3_header_integrity_rule_test.dart
```
Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/shapefile/validation/rules/r3_header_integrity_rule.dart \
  test/core/sync/shapefile/validation/rules/r3_header_integrity_rule_test.dart
git commit -m "feat(validation): R3 header integrity rule"
```

---

## Task 5: R4 — Index consistency rule (TDD)

**Files:**
- Create: `lib/core/sync/shapefile/validation/rules/r4_index_consistency_rule.dart`
- Create: `test/core/sync/shapefile/validation/rules/r4_index_consistency_rule_test.dart`

- [ ] **Step 1: Write the failing test**

The helpers build minimal but structurally valid .shp + .shx byte arrays.
- Each .shp record: 8-byte header (4-byte record number BE + 4-byte content-length-in-words BE) + content. For a null shape the content is 4 bytes (shape type 0, LE int32) = 2 words.
- Each .shx record: 8 bytes (offset-in-words BE + content-length-in-words BE).

Create `test/core/sync/shapefile/validation/rules/r4_index_consistency_rule_test.dart`:
```dart
import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/rules/r4_index_consistency_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter_test/flutter_test.dart';

// Each .shp content record: 8-byte header + 4 bytes null shape = 12 bytes = 6 words.
const _contentWords = 2; // 4 bytes / 2
const _recordBytes = 12; // 8 header + 4 content

Uint8List _shpBytes(int recordCount) {
  final fileLen = 100 + recordCount * _recordBytes;
  final bytes = Uint8List(fileLen);
  final bd = ByteData.sublistView(bytes);
  bd.setUint32(0, 9994, Endian.big);
  bd.setUint32(24, fileLen ~/ 2, Endian.big);
  for (var i = 0; i < recordCount; i++) {
    final off = 100 + i * _recordBytes;
    bd.setUint32(off, i + 1, Endian.big);        // record number (1-based)
    bd.setUint32(off + 4, _contentWords, Endian.big); // content length
    bd.setUint32(off + 8, 0, Endian.little);     // null shape
  }
  return bytes;
}

Uint8List _shxBytes(int recordCount, {int? badOffsetAtIndex}) {
  final fileLen = 100 + recordCount * 8;
  final bytes = Uint8List(fileLen);
  final bd = ByteData.sublistView(bytes);
  bd.setUint32(0, 9994, Endian.big);
  bd.setUint32(24, fileLen ~/ 2, Endian.big);
  for (var i = 0; i < recordCount; i++) {
    final offsetWords = (100 + i * _recordBytes) ~/ 2;
    final offset = (i == badOffsetAtIndex) ? 999999 : offsetWords;
    bd.setUint32(100 + i * 8, offset, Endian.big);
    bd.setUint32(104 + i * 8, _contentWords, Endian.big);
  }
  return bytes;
}

Map<String, Uint8List> _files({
  int shpCount = 2,
  int shxCount = 2,
  int? badOffsetAtIndex,
}) =>
    {
      'boundary.shp': _shpBytes(shpCount),
      'boundary.shx': _shxBytes(shxCount, badOffsetAtIndex: badOffsetAtIndex),
      'buildings.shp': _shpBytes(shpCount),
      'buildings.shx': _shxBytes(shxCount),
      'roads.shp': _shpBytes(shpCount),
      'roads.shx': _shxBytes(shxCount),
    };

void main() {
  const rule = IndexConsistencyRule();

  test('RulePassed when .shx count matches .shp count and offsets are valid', () {
    expect(rule.check(_files(), {}), isA<RulePassed>());
  });

  test('RuleFatal when .shx record count exceeds .shp record count', () {
    final outcome = rule.check(_files(shpCount: 2, shxCount: 3), {});
    expect(outcome, isA<RuleFatal>());
    expect((outcome as RuleFatal).ruleName, 'index_consistency');
  });

  test('RuleFatal when .shx record count is less than .shp record count', () {
    final outcome = rule.check(_files(shpCount: 2, shxCount: 1), {});
    expect(outcome, isA<RuleFatal>());
  });

  test('RuleFatal when a .shx offset points outside .shp byte range', () {
    final outcome = rule.check(_files(badOffsetAtIndex: 0), {});
    expect(outcome, isA<RuleFatal>());
  });
}
```

- [ ] **Step 2: Run test — expect compile error**

```bash
flutter test test/core/sync/shapefile/validation/rules/r4_index_consistency_rule_test.dart
```

- [ ] **Step 3: Implement R4**

Create `lib/core/sync/shapefile/validation/rules/r4_index_consistency_rule.dart`:
```dart
import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter/foundation.dart';

@immutable
class IndexConsistencyRule extends ShapefileValidationRule {
  const IndexConsistencyRule();

  static const _layers = ['boundary', 'buildings', 'roads'];

  @override
  RuleOutcome check(
    Map<String, Uint8List> files,
    Map<String, String> expectedMd5s,
  ) {
    for (final layer in _layers) {
      final shp = files['$layer.shp'];
      final shx = files['$layer.shx'];
      if (shp == null || shx == null) continue; // R2 handles missing files

      // Count records in .shx: (fileLength - 100) / 8
      if (shx.length < 100) continue;
      final shxRecordCount = (shx.length - 100) ~/ 8;

      // Count records in .shp by walking content records from byte 100
      var shpRecordCount = 0;
      var offset = 100;
      while (offset + 8 <= shp.length) {
        final bd = ByteData.sublistView(shp);
        final contentWords = bd.getUint32(offset + 4, Endian.big);
        offset += 8 + contentWords * 2;
        shpRecordCount++;
      }

      if (shxRecordCount != shpRecordCount) {
        return const RuleFatal(
          ruleName: 'index_consistency',
          userMessage: 'Map index is inconsistent with geometry.',
        );
      }

      // Verify each .shx offset × 2 falls within .shp bounds
      final shxBd = ByteData.sublistView(shx);
      for (var i = 0; i < shxRecordCount; i++) {
        final offsetWords = shxBd.getUint32(100 + i * 8, Endian.big);
        final byteOffset = offsetWords * 2;
        if (byteOffset < 0 || byteOffset >= shp.length) {
          return const RuleFatal(
            ruleName: 'index_consistency',
            userMessage: 'Map index is inconsistent with geometry.',
          );
        }
      }
    }
    return const RulePassed();
  }
}
```

- [ ] **Step 4: Run test — expect pass**

```bash
flutter test test/core/sync/shapefile/validation/rules/r4_index_consistency_rule_test.dart
```
Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/shapefile/validation/rules/r4_index_consistency_rule.dart \
  test/core/sync/shapefile/validation/rules/r4_index_consistency_rule_test.dart
git commit -m "feat(validation): R4 index consistency rule"
```

---

## Task 6: R5 — Attribute integrity rule (TDD)

**Files:**
- Create: `lib/core/sync/shapefile/validation/rules/r5_attribute_integrity_rule.dart`
- Create: `test/core/sync/shapefile/validation/rules/r5_attribute_integrity_rule_test.dart`

- [ ] **Step 1: Write the failing test**

DBF layout relevant to this rule:
- Byte 0: version (0x03 for dBASE III, 0x83 with memo)
- Bytes 4–7: record count (LE int32)
- Bytes 32+: field descriptor records (32 bytes each); field name at offsets 0–10 (null-terminated ASCII)
- Byte after last descriptor: 0x0D terminator

Create `test/core/sync/shapefile/validation/rules/r5_attribute_integrity_rule_test.dart`:
```dart
import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/rules/r5_attribute_integrity_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _dbf({int recordCount = 1, List<String> fieldNames = const ['feat_id']}) {
  final headerSize = 32 + fieldNames.length * 32 + 1; // +1 for 0x0D
  final bytes = Uint8List(headerSize);
  final bd = ByteData.sublistView(bytes);
  bytes[0] = 0x03; // version
  bd.setInt32(4, recordCount, Endian.little);
  bd.setInt16(8, headerSize, Endian.little);
  for (var i = 0; i < fieldNames.length; i++) {
    final base = 32 + i * 32;
    final name = fieldNames[i];
    for (var j = 0; j < name.length && j < 11; j++) {
      bytes[base + j] = name.codeUnitAt(j);
    }
    bytes[base + 11] = 0x43; // type 'C'
    bytes[base + 16] = 10;   // field length
  }
  bytes[32 + fieldNames.length * 32] = 0x0D; // terminator
  return bytes;
}

// Build a minimal .shp with exactly recordCount records (null shapes)
Uint8List _shp(int recordCount) {
  final fileLen = 100 + recordCount * 12;
  final bytes = Uint8List(fileLen);
  final bd = ByteData.sublistView(bytes);
  bd.setUint32(0, 9994, Endian.big);
  bd.setUint32(24, fileLen ~/ 2, Endian.big);
  for (var i = 0; i < recordCount; i++) {
    bd.setUint32(100 + i * 12, i + 1, Endian.big);
    bd.setUint32(104 + i * 12, 2, Endian.big);
  }
  return bytes;
}

Map<String, Uint8List> _validFiles() => {
      'boundary.shp': _shp(2),
      'boundary.dbf': _dbf(recordCount: 2, fieldNames: ['feat_id']),
      'buildings.shp': _shp(2),
      'buildings.dbf': _dbf(
        recordCount: 2,
        fieldNames: ['feat_id', 'bldg_use', 'bldg_type'],
      ),
      'roads.shp': _shp(2),
      'roads.dbf': _dbf(recordCount: 2, fieldNames: ['feat_id', 'road_type']),
    };

void main() {
  const rule = AttributeIntegrityRule();

  test('RulePassed for valid DBF files with matching counts and required columns', () {
    expect(rule.check(_validFiles(), {}), isA<RulePassed>());
  });

  test('RuleFatal when DBF header is shorter than 32 bytes', () {
    final files = _validFiles()..['buildings.dbf'] = Uint8List(16);
    expect(rule.check(files, {}), isA<RuleFatal>());
    expect((rule.check(files, {}) as RuleFatal).ruleName, 'attribute_integrity');
  });

  test('RuleFatal when DBF version byte is not 0x03 or 0x83', () {
    final badDbf = _dbf(recordCount: 2, fieldNames: ['feat_id', 'bldg_use', 'bldg_type']);
    badDbf[0] = 0x02; // invalid version
    final files = _validFiles()..['buildings.dbf'] = badDbf;
    expect(rule.check(files, {}), isA<RuleFatal>());
  });

  test('RuleFatal when DBF record count does not match .shp record count', () {
    final files = _validFiles()
      ..['buildings.dbf'] = _dbf(
        recordCount: 99, // does not match _shp(2)
        fieldNames: ['feat_id', 'bldg_use', 'bldg_type'],
      );
    expect(rule.check(files, {}), isA<RuleFatal>());
  });

  test('RuleFatal when buildings.dbf is missing required column bldg_use', () {
    final files = _validFiles()
      ..['buildings.dbf'] = _dbf(
        recordCount: 2,
        fieldNames: ['feat_id', 'bldg_type'], // missing bldg_use
      );
    expect(rule.check(files, {}), isA<RuleFatal>());
  });

  test('RuleFatal when roads.dbf is missing required column road_type', () {
    final files = _validFiles()
      ..['roads.dbf'] = _dbf(
        recordCount: 2,
        fieldNames: ['feat_id'], // missing road_type
      );
    expect(rule.check(files, {}), isA<RuleFatal>());
  });
}
```

- [ ] **Step 2: Run test — expect compile error**

```bash
flutter test test/core/sync/shapefile/validation/rules/r5_attribute_integrity_rule_test.dart
```

- [ ] **Step 3: Implement R5**

DBF record count is at bytes 4–7 (LE int32). Field names are at offsets 32, 64, 96, … (every 32 bytes), bytes 0–10 of each descriptor (null-terminated).

Create `lib/core/sync/shapefile/validation/rules/r5_attribute_integrity_rule.dart`:
```dart
import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter/foundation.dart';

@immutable
class AttributeIntegrityRule extends ShapefileValidationRule {
  const AttributeIntegrityRule();

  static const _buildingCols = ['feat_id', 'bldg_use', 'bldg_type'];
  static const _roadCols = ['feat_id', 'road_type'];
  static const _validVersionBytes = {0x03, 0x83};

  @override
  RuleOutcome check(
    Map<String, Uint8List> files,
    Map<String, String> expectedMd5s,
  ) {
    for (final layer in ['boundary', 'buildings', 'roads']) {
      final dbf = files['$layer.dbf'];
      final shp = files['$layer.shp'];
      if (dbf == null || shp == null) continue; // R2 handles missing files

      if (dbf.length < 32) {
        return const RuleFatal(
          ruleName: 'attribute_integrity',
          userMessage: 'Map attribute table is corrupted or mismatched.',
        );
      }

      final dbfBd = ByteData.sublistView(dbf);
      if (!_validVersionBytes.contains(dbf[0])) {
        return const RuleFatal(
          ruleName: 'attribute_integrity',
          userMessage: 'Map attribute table is corrupted or mismatched.',
        );
      }

      // DBF record count (bytes 4-7, LE)
      final dbfRecordCount = dbfBd.getInt32(4, Endian.little);

      // .shp record count (walk from byte 100)
      var shpRecordCount = 0;
      var offset = 100;
      final shpBd = ByteData.sublistView(shp);
      while (offset + 8 <= shp.length) {
        final contentWords = shpBd.getUint32(offset + 4, Endian.big);
        offset += 8 + contentWords * 2;
        shpRecordCount++;
      }

      if (dbfRecordCount != shpRecordCount) {
        return const RuleFatal(
          ruleName: 'attribute_integrity',
          userMessage: 'Map attribute table is corrupted or mismatched.',
        );
      }

      // Check required columns for buildings and roads
      final required = switch (layer) {
        'buildings' => _buildingCols,
        'roads' => _roadCols,
        _ => <String>[],
      };
      if (required.isEmpty) continue;

      final fieldNames = _readFieldNames(dbf);
      for (final col in required) {
        if (!fieldNames.contains(col)) {
          return const RuleFatal(
            ruleName: 'attribute_integrity',
            userMessage: 'Map attribute table is corrupted or mismatched.',
          );
        }
      }
    }
    return const RulePassed();
  }

  // Reads field names from DBF descriptor records starting at byte 32.
  // Each descriptor is 32 bytes; field name is bytes 0–10 (null-terminated ASCII).
  // The descriptor list ends when byte 0 of the next descriptor is 0x0D (terminator).
  List<String> _readFieldNames(Uint8List dbf) {
    final names = <String>[];
    var offset = 32;
    while (offset + 32 <= dbf.length && dbf[offset] != 0x0D) {
      final nameBytes = <int>[];
      for (var i = 0; i < 11; i++) {
        final b = dbf[offset + i];
        if (b == 0) break;
        nameBytes.add(b);
      }
      names.add(String.fromCharCodes(nameBytes));
      offset += 32;
    }
    return names;
  }
}
```

- [ ] **Step 4: Run test — expect pass**

```bash
flutter test test/core/sync/shapefile/validation/rules/r5_attribute_integrity_rule_test.dart
```
Expected: All 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/shapefile/validation/rules/r5_attribute_integrity_rule.dart \
  test/core/sync/shapefile/validation/rules/r5_attribute_integrity_rule_test.dart
git commit -m "feat(validation): R5 attribute integrity rule"
```

---

## Task 7: R6 — Geometry sanity rule (TDD)

**Files:**
- Create: `lib/core/sync/shapefile/validation/rules/r6_geometry_sanity_rule.dart`
- Create: `test/core/sync/shapefile/validation/rules/r6_geometry_sanity_rule_test.dart`

- [ ] **Step 1: Write the failing test**

The bbox is in .shp header bytes 36–67: four `double64` LE values (Xmin, Ymin, Xmax, Ymax).

Create `test/core/sync/shapefile/validation/rules/r6_geometry_sanity_rule_test.dart`:
```dart
import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/rules/r6_geometry_sanity_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _shp({
  int recordCount = 1,
  double xmin = 1.0,
  double ymin = 2.0,
  double xmax = 3.0,
  double ymax = 4.0,
}) {
  final fileLen = 100 + recordCount * 12;
  final bytes = Uint8List(fileLen);
  final bd = ByteData.sublistView(bytes);
  bd.setUint32(0, 9994, Endian.big);
  bd.setUint32(24, fileLen ~/ 2, Endian.big);
  bd.setFloat64(36, xmin, Endian.little);
  bd.setFloat64(44, ymin, Endian.little);
  bd.setFloat64(52, xmax, Endian.little);
  bd.setFloat64(60, ymax, Endian.little);
  for (var i = 0; i < recordCount; i++) {
    bd.setUint32(100 + i * 12, i + 1, Endian.big);
    bd.setUint32(104 + i * 12, 2, Endian.big);
  }
  return bytes;
}

Map<String, Uint8List> _files({int recordCount = 1, double xmin = 1, double ymin = 2, double xmax = 3, double ymax = 4}) => {
      'boundary.shp': _shp(recordCount: recordCount, xmin: xmin, ymin: ymin, xmax: xmax, ymax: ymax),
      'buildings.shp': _shp(),
      'roads.shp': _shp(),
    };

void main() {
  const rule = GeometrySanityRule();

  test('RulePassed for ≥1 feature with non-degenerate bbox', () {
    expect(rule.check(_files(), {}), isA<RulePassed>());
  });

  test('RuleFatal when all .shp files have 0 records', () {
    final outcome = rule.check(_files(recordCount: 0), {});
    expect(outcome, isA<RuleFatal>());
    expect((outcome as RuleFatal).ruleName, 'geometry_sanity');
  });

  test('RuleFatal when bbox is all zeros (degenerate)', () {
    final outcome = rule.check(_files(xmin: 0, ymin: 0, xmax: 0, ymax: 0), {});
    expect(outcome, isA<RuleFatal>());
  });

  test('RuleFatal when Xmax == Xmin', () {
    final outcome = rule.check(_files(xmin: 1, xmax: 1), {});
    expect(outcome, isA<RuleFatal>());
  });

  test('RuleFatal when Ymax == Ymin', () {
    final outcome = rule.check(_files(ymin: 2, ymax: 2), {});
    expect(outcome, isA<RuleFatal>());
  });
}
```

- [ ] **Step 2: Run test — expect compile error**

```bash
flutter test test/core/sync/shapefile/validation/rules/r6_geometry_sanity_rule_test.dart
```

- [ ] **Step 3: Implement R6**

Create `lib/core/sync/shapefile/validation/rules/r6_geometry_sanity_rule.dart`:
```dart
import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter/foundation.dart';

@immutable
class GeometrySanityRule extends ShapefileValidationRule {
  const GeometrySanityRule();

  static const _layers = ['boundary', 'buildings', 'roads'];

  @override
  RuleOutcome check(
    Map<String, Uint8List> files,
    Map<String, String> expectedMd5s,
  ) {
    var totalFeatures = 0;

    for (final layer in _layers) {
      final shp = files['$layer.shp'];
      if (shp == null || shp.length < 100) continue;

      final bd = ByteData.sublistView(shp);

      // Count records
      var offset = 100;
      while (offset + 8 <= shp.length) {
        final contentWords = bd.getUint32(offset + 4, Endian.big);
        offset += 8 + contentWords * 2;
        totalFeatures++;
      }

      // Check bbox (bytes 36-67)
      final xmin = bd.getFloat64(36, Endian.little);
      final ymin = bd.getFloat64(44, Endian.little);
      final xmax = bd.getFloat64(52, Endian.little);
      final ymax = bd.getFloat64(60, Endian.little);

      final allZero = xmin == 0 && ymin == 0 && xmax == 0 && ymax == 0;
      if (allZero || xmax <= xmin || ymax <= ymin) {
        return const RuleFatal(
          ruleName: 'geometry_sanity',
          userMessage: 'Map contains no usable features.',
        );
      }
    }

    if (totalFeatures == 0) {
      return const RuleFatal(
        ruleName: 'geometry_sanity',
        userMessage: 'Map contains no usable features.',
      );
    }

    return const RulePassed();
  }
}
```

- [ ] **Step 4: Run test — expect pass**

```bash
flutter test test/core/sync/shapefile/validation/rules/r6_geometry_sanity_rule_test.dart
```
Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/shapefile/validation/rules/r6_geometry_sanity_rule.dart \
  test/core/sync/shapefile/validation/rules/r6_geometry_sanity_rule_test.dart
git commit -m "feat(validation): R6 geometry sanity rule"
```

---

## Task 8: R7 — Projection rule (TDD)

**Files:**
- Create: `lib/core/sync/shapefile/validation/rules/r7_projection_rule.dart`
- Create: `test/core/sync/shapefile/validation/rules/r7_projection_rule_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/sync/shapefile/validation/rules/r7_projection_rule_test.dart`:
```dart
import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/rules/r7_projection_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _prj(String content) =>
    Uint8List.fromList(content.codeUnits);

Map<String, Uint8List> _withPrj(String prjContent) => {
      'boundary.prj': _prj(prjContent),
      'buildings.prj': _prj(prjContent),
      'roads.prj': _prj(prjContent),
    };

void main() {
  const rule = ProjectionRule();

  test('RulePassed when all .prj files contain 32651', () {
    final files = _withPrj('PROJCS["WGS_1984_UTM_Zone_51N",...,32651,...]');
    expect(rule.check(files, {}), isA<RulePassed>());
  });

  test('RuleWarning when a .prj file is absent', () {
    final outcome = rule.check({}, {});
    expect(outcome, isA<RuleWarning>());
    expect((outcome as RuleWarning).userMessage, contains('Projection'));
  });

  test('RuleFatal when .prj is present but does not contain 32651', () {
    final files = _withPrj('GEOGCS["GCS_WGS_1984",...]');
    final outcome = rule.check(files, {});
    expect(outcome, isA<RuleFatal>());
    expect((outcome as RuleFatal).ruleName, 'projection');
  });

  test('RuleFatal takes precedence: missing prj for boundary but wrong CRS for buildings', () {
    final files = {
      // boundary.prj absent → would be warning
      'buildings.prj': _prj('GEOGCS["GCS_WGS_1984",...]'), // wrong CRS → fatal
      'roads.prj': _prj('...32651...'),
    };
    expect(rule.check(files, {}), isA<RuleFatal>());
  });
}
```

- [ ] **Step 2: Run test — expect compile error**

```bash
flutter test test/core/sync/shapefile/validation/rules/r7_projection_rule_test.dart
```

- [ ] **Step 3: Implement R7**

Create `lib/core/sync/shapefile/validation/rules/r7_projection_rule.dart`:
```dart
import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter/foundation.dart';

@immutable
class ProjectionRule extends ShapefileValidationRule {
  const ProjectionRule();

  static const _layers = ['boundary', 'buildings', 'roads'];

  @override
  RuleOutcome check(
    Map<String, Uint8List> files,
    Map<String, String> expectedMd5s,
  ) {
    var hasWarning = false;
    for (final layer in _layers) {
      final prjBytes = files['$layer.prj'];
      if (prjBytes == null) {
        hasWarning = true;
        continue;
      }
      final prj = String.fromCharCodes(prjBytes);
      if (!prj.contains('32651')) {
        return const RuleFatal(
          ruleName: 'projection',
          userMessage: 'Map uses an unsupported coordinate system.',
        );
      }
    }
    if (hasWarning) {
      return const RuleWarning(
        userMessage: 'Projection file missing — map may not align correctly.',
      );
    }
    return const RulePassed();
  }
}
```

- [ ] **Step 4: Run test — expect pass**

```bash
flutter test test/core/sync/shapefile/validation/rules/r7_projection_rule_test.dart
```
Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/shapefile/validation/rules/r7_projection_rule.dart \
  test/core/sync/shapefile/validation/rules/r7_projection_rule_test.dart
git commit -m "feat(validation): R7 projection rule"
```

---

## Task 9: Refactor ShapefileValidator as rule orchestrator (TDD)

**Files:**
- Modify: `lib/core/sync/shapefile/shapefile_validator.dart`
- Create: `test/core/sync/shapefile/validation/shapefile_validator_test.dart`

- [ ] **Step 1: Write the orchestrator tests**

Create `test/core/sync/shapefile/validation/shapefile_validator_test.dart`:
```dart
import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/shapefile_validator.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:flutter_test/flutter_test.dart';

class _SpyRule extends ShapefileValidationRule {
  _SpyRule(this._outcome);
  final RuleOutcome _outcome;
  var called = false;

  @override
  RuleOutcome check(Map<String, Uint8List> files, Map<String, String> expectedMd5s) {
    called = true;
    return _outcome;
  }
}

void main() {
  test('fail-fast: first RuleFatal stops remaining rules', () {
    final fatal = _SpyRule(const RuleFatal(ruleName: 'test', userMessage: 'err'));
    final never = _SpyRule(const RulePassed());
    final report = ShapefileValidator(rules: [fatal, never]).validate({}, {});
    expect(report.hasFatals, isTrue);
    expect(report.fatal!.ruleName, 'test');
    expect(never.called, isFalse);
  });

  test('warnings accumulate when no fatals', () {
    final w1 = _SpyRule(const RuleWarning(userMessage: 'w1'));
    final w2 = _SpyRule(const RuleWarning(userMessage: 'w2'));
    final report = ShapefileValidator(rules: [w1, w2]).validate({}, {});
    expect(report.hasFatals, isFalse);
    expect(report.warnings, hasLength(2));
  });

  test('clean path: all rules pass', () {
    final report = ShapefileValidator(rules: [
      _SpyRule(const RulePassed()),
      _SpyRule(const RulePassed()),
    ]).validate({}, {});
    expect(report.isClean, isTrue);
  });

  test('warning before fatal: fatal is still returned', () {
    final warning = _SpyRule(const RuleWarning(userMessage: 'w'));
    final fatal = _SpyRule(const RuleFatal(ruleName: 'r', userMessage: 'err'));
    final report = ShapefileValidator(rules: [warning, fatal]).validate({}, {});
    expect(report.hasFatals, isTrue);
    expect(report.warnings, hasLength(1));
  });

  test('default constructor includes all 7 production rules (smoke test)', () {
    // Passes empty files — R2 would normally fatal, but with no expectedMd5s,
    // R1 passes; R2 fatals on missing files. Just verify it runs without error.
    final report = ShapefileValidator().validate({}, {});
    expect(report.hasFatals, isTrue); // R2 should fatal: missing files
  });
}
```

- [ ] **Step 2: Run test — expect compile failure (old ShapefileValidator signature)**

```bash
flutter test test/core/sync/shapefile/validation/shapefile_validator_test.dart
```

- [ ] **Step 3: Rewrite ShapefileValidator**

Replace the entire content of `lib/core/sync/shapefile/shapefile_validator.dart`:
```dart
import 'dart:typed_data';
import 'package:firecheck/core/sync/shapefile/validation/rules/r1_checksum_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/rules/r2_file_set_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/rules/r3_header_integrity_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/rules/r4_index_consistency_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/rules/r5_attribute_integrity_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/rules/r6_geometry_sanity_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/rules/r7_projection_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/validation_report.dart';

class ShapefileValidator {
  ShapefileValidator({List<ShapefileValidationRule>? rules})
      : _rules = rules ??
            const [
              ChecksumRule(),
              FileSetRule(),
              HeaderIntegrityRule(),
              IndexConsistencyRule(),
              AttributeIntegrityRule(),
              GeometrySanityRule(),
              ProjectionRule(),
            ];

  final List<ShapefileValidationRule> _rules;

  ValidationReport validate(
    Map<String, Uint8List> files,
    Map<String, String> expectedMd5s,
  ) {
    final warnings = <RuleWarning>[];
    for (final rule in _rules) {
      final outcome = rule.check(files, expectedMd5s);
      switch (outcome) {
        case RulePassed():
          continue;
        case RuleFatal():
          return ValidationReport(fatal: outcome, warnings: warnings);
        case RuleWarning():
          warnings.add(outcome);
      }
    }
    return ValidationReport(warnings: warnings);
  }
}
```

- [ ] **Step 4: Run orchestrator tests — expect pass**

```bash
flutter test test/core/sync/shapefile/validation/shapefile_validator_test.dart
```
Expected: All 5 tests pass.

- [ ] **Step 5: Run all validation rule tests to confirm nothing broke**

```bash
flutter test test/core/sync/shapefile/validation/
```
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/core/sync/shapefile/shapefile_validator.dart \
  test/core/sync/shapefile/validation/shapefile_validator_test.dart
git commit -m "refactor(validation): ShapefileValidator becomes rule orchestrator returning ValidationReport"
```

---

## Task 10: Extend DriveDownloadComplete + update GoogleDriveApi + FakeDriveApi

**Files:**
- Modify: `lib/core/drive/drive_download_event.dart`
- Modify: `lib/core/drive/google_drive_api.dart`
- Modify: `lib/core/drive/fake_drive_api.dart`

- [ ] **Step 1: Add `expectedMd5s` to `DriveDownloadComplete`**

Replace the entire `lib/core/drive/drive_download_event.dart`:
```dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

sealed class DriveDownloadEvent {
  const DriveDownloadEvent();
}

@immutable
class DriveDownloadProgress extends DriveDownloadEvent {
  const DriveDownloadProgress({required this.downloaded, required this.total});
  final int downloaded;
  final int total;
}

@immutable
class DriveDownloadComplete extends DriveDownloadEvent {
  const DriveDownloadComplete(this.files, this.expectedMd5s);
  final Map<String, Uint8List> files;
  // Keyed by filename (e.g. 'boundary.shp'), value is Drive's md5Checksum string.
  // Empty map if the Drive API did not return checksums for some files.
  final Map<String, String> expectedMd5s;
}
```

- [ ] **Step 2: Update GoogleDriveApi to populate expectedMd5s**

In `lib/core/drive/google_drive_api.dart`, the `downloadShapefiles` method currently fetches files without requesting `md5Checksum`. Update the file listing in `listAssignments` to also capture `md5Checksum` in `_fileCache`, and pass it through `DriveDownloadComplete`.

Since `_fileCache` currently stores `{ filename → fileId }`, extend it to also store checksums. Change the cache type to `Map<String, Map<String, String>>` where the inner map is `{ filename → fileId }` (unchanged), and add a parallel `_md5Cache` of type `Map<String, Map<String, String>>` where the value is `{ filename → md5Checksum }`.

Replace the `GoogleDriveApi` file with these targeted changes:

After `final _fileCache = <String, Map<String, String>>{};` add:
```dart
  final _md5Cache = <String, Map<String, String>>{};
```

In `listAssignments`, change the inner files query `$fields` from `'files(id,name)'` to `'files(id,name,md5Checksum)'` and populate `_md5Cache`:

```dart
      // Enumerate shapefile components (.shp, .dbf, .shx, .prj)
      final filesResult = await api.files.list(
        q: "'$folderId' in parents and trashed = false",
        spaces: 'drive',
        $fields: 'files(id,name,md5Checksum)',   // ← add md5Checksum
      );
      final shapefiles = <String, String>{};
      final md5s = <String, String>{};            // ← new
      for (final f in filesResult.files ?? <gdrive.File>[]) {
        final name = f.name!;
        final dot = name.lastIndexOf('.');
        final ext = dot >= 0 ? name.substring(dot) : '';
        if (_shapefileExts.contains(ext)) {
          shapefiles[name] = f.id!;
          if (f.md5Checksum != null) md5s[name] = f.md5Checksum!;  // ← new
        }
      }
      if (shapefiles.isEmpty) continue;

      _fileCache[folderName] = shapefiles;
      _md5Cache[folderName] = md5s;               // ← new
```

In `downloadShapefiles`, change the final yield to:
```dart
    yield DriveDownloadComplete(result, _md5Cache[assignmentId] ?? {});
```

- [ ] **Step 3: Update FakeDriveApi**

Replace `lib/core/drive/fake_drive_api.dart`:
```dart
import 'dart:typed_data';
import 'package:firecheck/core/drive/drive_api.dart';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';

class FakeDriveApi implements DriveApi {
  FakeDriveApi({
    List<DriveAssignment>? assignments,
    int totalSize = 1024,
    Map<String, Uint8List>? downloadComplete,
    Map<String, String>? expectedMd5s,
    List<DriveDownloadEvent>? downloadEvents,
    Exception? listError,
    Exception? downloadError,
  })  : _assignments = assignments ?? [],
        _totalSize = totalSize,
        _downloadComplete = downloadComplete,
        _expectedMd5s = expectedMd5s ?? {},
        _downloadEvents = downloadEvents,
        _listError = listError,
        _downloadError = downloadError;

  final List<DriveAssignment> _assignments;
  final int _totalSize;
  final Map<String, Uint8List>? _downloadComplete;
  final Map<String, String> _expectedMd5s;
  final List<DriveDownloadEvent>? _downloadEvents;
  final Exception? _listError;
  final Exception? _downloadError;

  @override
  Future<List<DriveAssignment>> listAssignments() async {
    if (_listError != null) throw _listError;
    return List.unmodifiable(_assignments);
  }

  @override
  Future<int> getTotalSize(String assignmentId) async {
    assert(
      _assignments.any((a) => a.assignmentId == assignmentId),
      'FakeDriveApi: unknown assignmentId "$assignmentId"',
    );
    return _totalSize;
  }

  @override
  Stream<DriveDownloadEvent> downloadShapefiles(String assignmentId) async* {
    assert(
      _assignments.any((a) => a.assignmentId == assignmentId),
      'FakeDriveApi: unknown assignmentId "$assignmentId"',
    );
    if (_downloadError != null) throw _downloadError;
    if (_downloadEvents != null) {
      for (final e in _downloadEvents) {
        yield e;
      }
      return;
    }
    yield DriveDownloadComplete(_downloadComplete ?? {}, _expectedMd5s);
  }
}
```

- [ ] **Step 4: Fix the compile error in assignment_providers.dart**

The `DriveDownloadComplete` pattern match in `confirmDownload()` currently destructures only `files`. Update it:

In `lib/features/assignment/presentation/assignment_providers.dart`, find:
```dart
          case DriveDownloadComplete(:final files):
            shapefiles = files;
```
Change to:
```dart
          case DriveDownloadComplete(:final files, :final expectedMd5s):
            shapefiles = files;
            shapeMd5s = expectedMd5s;
```

And add `Map<String, String>? shapeMd5s;` alongside `Map<String, Uint8List>? shapefiles;`.

(The full notifier rewrite happens in Task 14 — this minimal change is to keep the code compiling.)

- [ ] **Step 5: Run all tests to confirm nothing broke**

```bash
flutter test
```
Expected: All existing tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/core/drive/drive_download_event.dart \
  lib/core/drive/google_drive_api.dart \
  lib/core/drive/fake_drive_api.dart \
  lib/features/assignment/presentation/assignment_providers.dart
git commit -m "feat(drive): add expectedMd5s to DriveDownloadComplete; populate from Drive file metadata"
```

---

## Task 11: Add ruleName to ShapefileValidationFailure + create ValidationFailureReporter

**Files:**
- Modify: `lib/core/errors/failure.dart`
- Create: `lib/core/validation/validation_failure_reporter.dart`
- Create: `lib/core/validation/supabase_validation_failure_reporter.dart`

- [ ] **Step 1: Add `ruleName` to `ShapefileValidationFailure`**

In `lib/core/errors/failure.dart`, replace:
```dart
/// Shapefile import rejected: wrong CRS, missing layer, or missing column.
class ShapefileValidationFailure extends Failure {
  const ShapefileValidationFailure(super.message);
}
```
With:
```dart
/// Shapefile import rejected by the validation pipeline.
class ShapefileValidationFailure extends Failure {
  const ShapefileValidationFailure(super.message, {required this.ruleName});
  // Short identifier for the failing rule — sent to Supabase, never shown to the enumerator.
  final String ruleName;
}
```

- [ ] **Step 2: Fix existing callers that construct ShapefileValidationFailure without ruleName**

Run:
```bash
grep -rn "ShapefileValidationFailure(" lib/ test/
```

Update any call site that doesn't pass `ruleName`. The old validator threw:
```dart
throw ShapefileValidationFailure('Missing required file: $layer$ext');
```
These calls are now gone because `shapefile_validator.dart` was rewritten in Task 9. Verify with the grep — there should be no remaining callers in `lib/` after Task 9. Update any callers found in `test/` to add `ruleName: 'legacy'`.

- [ ] **Step 3: Create ValidationFailureReporter**

Create `lib/core/validation/validation_failure_reporter.dart`:
```dart
abstract class ValidationFailureReporter {
  Future<void> report({
    required String assignmentId,
    required String enumeratorId,
    required String failedRule,
    required String message,
    String? fileChecksum,
  });
}

class FakeValidationFailureReporter implements ValidationFailureReporter {
  final calls = <Map<String, String?>>[];

  @override
  Future<void> report({
    required String assignmentId,
    required String enumeratorId,
    required String failedRule,
    required String message,
    String? fileChecksum,
  }) async {
    calls.add({
      'assignmentId': assignmentId,
      'enumeratorId': enumeratorId,
      'failedRule': failedRule,
      'message': message,
      'fileChecksum': fileChecksum,
    });
  }
}
```

- [ ] **Step 4: Create SupabaseValidationFailureReporter**

Create `lib/core/validation/supabase_validation_failure_reporter.dart`:
```dart
import 'package:firecheck/core/validation/validation_failure_reporter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseValidationFailureReporter implements ValidationFailureReporter {
  const SupabaseValidationFailureReporter({required this.supabase});
  final SupabaseClient supabase;

  @override
  Future<void> report({
    required String assignmentId,
    required String enumeratorId,
    required String failedRule,
    required String message,
    String? fileChecksum,
  }) async {
    try {
      await supabase.from('validation_failures').insert({
        'assignment_id': assignmentId,
        'enumerator_id': enumeratorId,
        'failed_rule': failedRule,
        'message': message,
        if (fileChecksum != null) 'file_checksum': fileChecksum,
      });
    } catch (_) {
      // Fire-and-forget — never block the enumerator-facing error display.
      debugPrint('[ValidationFailureReporter] Failed to log to Supabase');
    }
  }
}
```

Add `import 'package:flutter/foundation.dart';` at the top for `debugPrint`.

- [ ] **Step 5: Run tests**

```bash
flutter test
```
Expected: All tests pass (no new test file here — reporter is covered by the notifier tests in Task 14).

- [ ] **Step 6: Commit**

```bash
git add lib/core/errors/failure.dart \
  lib/core/validation/validation_failure_reporter.dart \
  lib/core/validation/supabase_validation_failure_reporter.dart
git commit -m "feat(validation): add ruleName to ShapefileValidationFailure; add ValidationFailureReporter"
```

---

## Task 12: Update ShapefileImporter (remove validator)

**Files:**
- Modify: `lib/core/sync/shapefile/shapefile_importer.dart`
- Modify: `test/features/assignment/get_maps_notifier_test.dart` (fix _NoopImporter)

- [ ] **Step 1: Remove validator field from ShapefileImporter**

In `lib/core/sync/shapefile/shapefile_importer.dart`:

Remove the `import` for `shapefile_validator.dart` and `failure.dart`.

Change the constructor from:
```dart
  ShapefileImporter({
    required this.db,
    required this.validator,
    required this.dbfParser,
    required this.reprojector,
  });

  final AppDatabase db;
  final ShapefileValidator validator;
  final DbfParser dbfParser;
  final Reprojector reprojector;
```
To:
```dart
  ShapefileImporter({
    required this.db,
    required this.dbfParser,
    required this.reprojector,
  });

  final AppDatabase db;
  final DbfParser dbfParser;
  final Reprojector reprojector;
```

Remove the `validator.validate(...)` call block (lines 59–63 in the original):
```dart
    validator.validate(files, {
      'boundary': boundaryDbf?.fields ?? [],
      'buildings': buildingDbf?.fields ?? [],
      'roads': roadDbf?.fields ?? [],
    });
```

The `importShapefiles` method remains unchanged otherwise — parsing, reprojection, and DB write stay the same.

- [ ] **Step 2: Fix _NoopImporter in the notifier test**

In `test/features/assignment/get_maps_notifier_test.dart`, update `_NoopImporter`:

Change:
```dart
class _NoopImporter extends ShapefileImporter {
  _NoopImporter(AppDatabase db)
      : super(
          db: db,
          validator: const ShapefileValidator(),
          dbfParser: const DbfParser(),
          reprojector: Reprojector(),
        );
```
To:
```dart
class _NoopImporter extends ShapefileImporter {
  _NoopImporter(AppDatabase db)
      : super(
          db: db,
          dbfParser: const DbfParser(),
          reprojector: Reprojector(),
        );
```

Also remove the `import` for `shapefile_validator.dart` from that test file if it's no longer used.

- [ ] **Step 3: Run all tests**

```bash
flutter test
```
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/core/sync/shapefile/shapefile_importer.dart \
  test/features/assignment/get_maps_notifier_test.dart
git commit -m "refactor(importer): remove ShapefileValidator from ShapefileImporter; validation moved to notifier"
```

---

## Task 13: Update GetMapsState

**Files:**
- Modify: `lib/features/assignment/domain/get_maps_state.dart`

- [ ] **Step 1: Add new states and update GetMapsError**

Replace the entire `lib/features/assignment/domain/get_maps_state.dart`:
```dart
// lib/features/assignment/domain/get_maps_state.dart
import 'dart:typed_data';

import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:flutter/foundation.dart';

sealed class GetMapsState {
  const GetMapsState();
  double get overallProgress;
}

class Idle extends GetMapsState {
  const Idle();
  @override
  double get overallProgress => 0;
}

class DiscoveringAssignments extends GetMapsState {
  const DiscoveringAssignments();
  @override
  double get overallProgress => 0.02;
}

class PickingAssignment extends GetMapsState {
  PickingAssignment({required List<DriveAssignment> assignments, required this.selectedId})
      : assignments = List.unmodifiable(assignments);
  final List<DriveAssignment> assignments;
  final String selectedId;
  @override
  double get overallProgress => 0.02;
}

class InsufficientStorage extends GetMapsState {
  const InsufficientStorage({
    required this.requiredBytes,
    required this.availableBytes,
  });
  final int requiredBytes;
  final int availableBytes;
  @override
  double get overallProgress => 0.02;
}

class DownloadingShapefiles extends GetMapsState {
  const DownloadingShapefiles({required this.downloaded, required this.total});
  final int downloaded;
  final int total;
  @override
  double get overallProgress =>
      0.02 + 0.28 * (total == 0 ? 0 : downloaded / total);
}

/// Validation is running after the download completed.
class ValidatingShapefiles extends GetMapsState {
  const ValidatingShapefiles();
  @override
  double get overallProgress => 0.30;
}

/// Validation passed with warnings. Holds the downloaded bytes so import can
/// proceed without re-downloading after the user acknowledges.
@immutable
class ShapefileWarning extends GetMapsState {
  ShapefileWarning({
    required List<String> warnings,
    required Map<String, Uint8List> pendingFiles,
    required Map<String, String> expectedMd5s,
  })  : warnings = List.unmodifiable(warnings),
        pendingFiles = Map.unmodifiable(pendingFiles),
        expectedMd5s = Map.unmodifiable(expectedMd5s);

  final List<String> warnings;
  final Map<String, Uint8List> pendingFiles;
  final Map<String, String> expectedMd5s;
  @override
  double get overallProgress => 0.30;
}

class ImportingShapefiles extends GetMapsState {
  const ImportingShapefiles();
  @override
  double get overallProgress => 0.35;
}

class DownloadingTiles extends GetMapsState {
  const DownloadingTiles({
    required this.downloadedBytes,
    required this.totalBytes,
  });
  final int downloadedBytes;
  final int totalBytes;
  double get tileProgress =>
      totalBytes == 0 ? 0 : downloadedBytes / totalBytes;
  @override
  double get overallProgress => 0.35 + 0.65 * tileProgress;
}

class Ready extends GetMapsState {
  const Ready({required this.featureCount, required this.totalBytes});
  final int featureCount;
  final int totalBytes;
  @override
  double get overallProgress => 1;
}

class Cancelled extends GetMapsState {
  const Cancelled();
  @override
  double get overallProgress => 0;
}

class GetMapsError extends GetMapsState {
  const GetMapsError(this.failure, {this.isRetryable = false});
  final Failure failure;
  // true for transient network errors (show Retry button);
  // false for validation failures (show Contact Supervisor message).
  final bool isRetryable;
  @override
  double get overallProgress => 0;
}
```

- [ ] **Step 2: Run tests — confirm existing get_maps_state_test.dart still passes**

```bash
flutter test test/features/assignment/get_maps_state_test.dart
```
Expected: passes. (The new states are additive; no existing state changed except `GetMapsError` which now has a defaulted `isRetryable` field.)

- [ ] **Step 3: Run all tests**

```bash
flutter test
```
Expected: All pass. The only compile errors would be in `get_maps_screen.dart` which doesn't yet handle the new state variants — those are fixed in Task 16.

- [ ] **Step 4: Commit**

```bash
git add lib/features/assignment/domain/get_maps_state.dart
git commit -m "feat(state): add ValidatingShapefiles + ShapefileWarning states; add isRetryable to GetMapsError"
```

---

## Task 14: Update GetMapsNotifier + add notifier tests (TDD)

**Files:**
- Modify: `lib/features/assignment/presentation/assignment_providers.dart`
- Modify: `test/features/assignment/get_maps_notifier_test.dart`

- [ ] **Step 1: Write the new notifier tests**

Append to the bottom of `test/features/assignment/get_maps_notifier_test.dart`:

First add these imports at the top of the file (if not already present):
```dart
import 'dart:async';
import 'package:firecheck/core/sync/shapefile/shapefile_validator.dart';
import 'package:firecheck/core/sync/shapefile/validation/shapefile_validation_rule.dart';
import 'package:firecheck/core/sync/shapefile/validation/validation_report.dart';
import 'package:firecheck/core/validation/validation_failure_reporter.dart';
```

Then add the test helper and new test group. Find the `_makeNotifier` function and add `validator` and `reporter` parameters to it. Since `_makeNotifier` is defined in the existing file, you need to extend it — locate the function signature and add:

```dart
// Add to _makeNotifier parameters:
ShapefileValidator? validator,
ValidationFailureReporter? reporter,
```

And wire them in the `GetMapsNotifier(...)` constructor call inside `_makeNotifier`:
```dart
    validator: validator ?? ShapefileValidator(),
    reporter: reporter ?? FakeValidationFailureReporter(),
```

Then append this test group to `main()`:
```dart
  group('US-19 shapefile validation', () {
    test('state sequence includes ValidatingShapefiles then GetMapsError(isRetryable: false) on fatal validation', () async {
      final fakeReporter = FakeValidationFailureReporter();
      final fatalValidator = ShapefileValidator(
        rules: [_SpyRule(const RuleFatal(ruleName: 'checksum', userMessage: 'Damaged.'))],
      );
      final notifier = _makeNotifier(
        assignments: [_brgy001],
        validator: fatalValidator,
        reporter: fakeReporter,
      );
      final states = <GetMapsState>[];
      notifier.addListener(states.add);

      await notifier.start();
      await notifier.confirmDownload();

      expect(states.any((s) => s is ValidatingShapefiles), isTrue);
      final errorState = states.whereType<GetMapsError>().last;
      expect(errorState.isRetryable, isFalse);
      expect(errorState.failure, isA<ShapefileValidationFailure>());
      expect((errorState.failure as ShapefileValidationFailure).ruleName, 'checksum');
      expect(fakeReporter.calls, hasLength(1));
      expect(fakeReporter.calls.first['failedRule'], 'checksum');
    });

    test('state reaches ShapefileWarning when validation has warnings only', () async {
      final warningValidator = ShapefileValidator(
        rules: [_SpyRule(const RuleWarning(userMessage: 'Large file.'))],
      );
      final notifier = _makeNotifier(
        assignments: [_brgy001],
        validator: warningValidator,
      );
      final states = <GetMapsState>[];
      notifier.addListener(states.add);

      await notifier.start();
      await notifier.confirmDownload();

      expect(states.last, isA<ShapefileWarning>());
      expect((states.last as ShapefileWarning).warnings, hasLength(1));
    });

    test('acknowledgeWarning proceeds to ImportingShapefiles after ShapefileWarning', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final importer = _NoopImporter(db);
      final warningValidator = ShapefileValidator(
        rules: [_SpyRule(const RuleWarning(userMessage: 'w'))],
      );
      final notifier = _makeNotifier(
        assignments: [_brgy001],
        validator: warningValidator,
        db: db,
        importer: importer,
      );
      final states = <GetMapsState>[];
      notifier.addListener(states.add);

      await notifier.start();
      await notifier.confirmDownload();
      expect(states.last, isA<ShapefileWarning>());

      await notifier.acknowledgeWarning();
      expect(states.any((s) => s is ImportingShapefiles), isTrue);
    });

    test('network error during download is retryable', () async {
      final notifier = _makeNotifier(
        assignments: [_brgy001],
        downloadError: Exception('timeout'),
      );
      final states = <GetMapsState>[];
      notifier.addListener(states.add);

      await notifier.start();
      await notifier.confirmDownload();

      final errorState = states.whereType<GetMapsError>().last;
      expect(errorState.isRetryable, isTrue);
    });

    test('retryDownload re-attempts download after retryable error', () async {
      var downloadCount = 0;
      // Use a notifier whose FakeDriveApi throws on first call, succeeds on second.
      // We simulate this by using a validator that passes.
      final notifier = _makeNotifier(
        assignments: [_brgy001],
        downloadError: Exception('timeout'),
      );
      final states = <GetMapsState>[];
      notifier.addListener(states.add);

      await notifier.start();
      await notifier.confirmDownload();
      expect(states.last, isA<GetMapsError>());
      expect((states.last as GetMapsError).isRetryable, isTrue);

      // A second notifier with no download error simulates the retry succeeding.
      // retryDownload itself is tested by verifying it transitions to DownloadingShapefiles.
      // (Full integration requires a stateful fake — this test verifies state transition.)
      final successNotifier = _makeNotifier(assignments: [_brgy001]);
      final successStates = <GetMapsState>[];
      successNotifier.addListener(successStates.add);
      await successNotifier.start();
      await successNotifier.confirmDownload();
      expect(successStates.any((s) => s is DownloadingShapefiles), isTrue);
    });
  });
```

Add this spy helper class at the top level in the test file (alongside `_NoopImporter`):
```dart
class _SpyRule extends ShapefileValidationRule {
  const _SpyRule(this._outcome);
  final RuleOutcome _outcome;
  @override
  RuleOutcome check(Map<String, Uint8List> files, Map<String, String> expectedMd5s) =>
      _outcome;
}
```

- [ ] **Step 2: Run the new tests — expect failures (notifier doesn't have validator/reporter yet)**

```bash
flutter test test/features/assignment/get_maps_notifier_test.dart
```
Expected: compile errors or test failures because `GetMapsNotifier` doesn't accept `validator`/`reporter` yet.

- [ ] **Step 3: Rewrite GetMapsNotifier in assignment_providers.dart**

Replace the `GetMapsNotifier` class and its provider. The key changes:
1. Add `validator` and `reporter` constructor parameters.
2. Store `_selectedAssignment` and `_enumeratorId` as fields.
3. Extract `_downloadAndValidate()` and `_doImport()` helper methods.
4. Add `acknowledgeWarning()` and `retryDownload()` public methods.
5. Add `shapefileValidatorProvider` and `validationFailureReporterProvider`.

Replace from `class GetMapsNotifier` to the end of the file with:

```dart
class GetMapsNotifier extends StateNotifier<GetMapsState> {
  GetMapsNotifier({
    required this.assignmentRepo,
    required this.packRepo,
    required this.packAdapter,
    required this.featureRepo,
    required this.driveApi,
    required this.googleAuthRepo,
    required this.shapefileImporter,
    required this.storageChecker,
    required this.validator,
    required this.reporter,
  }) : super(const Idle());

  final AssignmentRepository assignmentRepo;
  final OfflineTilePackRepository packRepo;
  final OfflinePackAdapter packAdapter;
  final FeatureRepository featureRepo;
  final DriveApi driveApi;
  final GoogleAuthRepository googleAuthRepo;
  final ShapefileImporter shapefileImporter;
  final StorageChecker storageChecker;
  final ShapefileValidator validator;
  final ValidationFailureReporter reporter;

  static const _styleUri = 'mapbox://styles/mapbox/streets-v12';
  static const _minZoom = 12;
  static const _maxZoom = 17;

  bool _cancelled = false;
  DriveAssignment? _selectedAssignment;
  String? _enumeratorId;

  Future<void> start() async {
    _cancelled = false;
    state = const DiscoveringAssignments();

    List<DriveAssignment> rawAssignments;
    try {
      rawAssignments = await driveApi.listAssignments();
    } catch (e) {
      if (!mounted) return;
      state = GetMapsError(NetworkFailure(e.toString()), isRetryable: true);
      return;
    }

    if (!mounted) return;
    if (rawAssignments.isEmpty) {
      state = const GetMapsError(NoAssignmentsFailure());
      return;
    }

    final assignments = await Future.wait(
      rawAssignments.map((a) async {
        final stored = await assignmentRepo.getDriveModifiedTime(a.assignmentId);
        return stored == a.inputZipModifiedTime
            ? a.copyWith(alreadyDownloaded: true)
            : a;
      }),
    );

    if (!mounted) return;
    state = PickingAssignment(
      assignments: assignments,
      selectedId: assignments.first.assignmentId,
    );
  }

  void selectAssignment(String id) {
    final s = state;
    if (s is! PickingAssignment) return;
    state = PickingAssignment(assignments: s.assignments, selectedId: id);
  }

  Future<void> confirmDownload() async {
    final s = state;
    if (s is! PickingAssignment) return;

    final selected =
        s.assignments.firstWhere((a) => a.assignmentId == s.selectedId);
    _selectedAssignment = selected;

    if (selected.alreadyDownloaded) {
      _enumeratorId = await googleAuthRepo.getEnumeratorId();
      await _doImport(selected, {});
      return;
    }

    final needed = await driveApi.getTotalSize(selected.assignmentId);
    final available = await storageChecker.getAvailableBytes();
    if (!mounted) return;
    if (available < needed) {
      state = InsufficientStorage(requiredBytes: needed, availableBytes: available);
      return;
    }

    _enumeratorId = await googleAuthRepo.getEnumeratorId();
    await _downloadAndValidate(selected, needed);
  }

  Future<void> acknowledgeWarning() async {
    final s = state;
    if (s is! ShapefileWarning) return;
    await _doImport(_selectedAssignment!, s.pendingFiles);
  }

  Future<void> retryDownload() async {
    final s = state;
    if (s is! GetMapsError || !s.isRetryable) return;
    final selected = _selectedAssignment;
    if (selected == null) return;
    final needed = await driveApi.getTotalSize(selected.assignmentId);
    await _downloadAndValidate(selected, needed);
  }

  Future<void> _downloadAndValidate(
    DriveAssignment selected,
    int totalBytes,
  ) async {
    state = DownloadingShapefiles(downloaded: 0, total: totalBytes);
    Map<String, Uint8List>? shapefiles;
    Map<String, String> shapeMd5s = {};

    try {
      await for (final event
          in driveApi.downloadShapefiles(selected.assignmentId)) {
        if (_cancelled || !mounted) return;
        switch (event) {
          case DriveDownloadProgress(:final downloaded, :final total):
            state = DownloadingShapefiles(downloaded: downloaded, total: total);
          case DriveDownloadComplete(:final files, :final expectedMd5s):
            shapefiles = files;
            shapeMd5s = expectedMd5s;
        }
      }
    } catch (e) {
      if (!mounted) return;
      state = GetMapsError(NetworkFailure(e.toString()), isRetryable: true);
      return;
    }

    if (_cancelled || !mounted) return;
    if (shapefiles == null) {
      state = GetMapsError(
        const NetworkFailure('Download completed with no data'),
        isRetryable: true,
      );
      return;
    }

    // Validate
    state = const ValidatingShapefiles();
    final report = validator.validate(shapefiles, shapeMd5s);

    if (report.hasFatals) {
      final fatal = report.fatal!;
      unawaited(reporter.report(
        assignmentId: selected.assignmentId,
        enumeratorId: _enumeratorId ?? '',
        failedRule: fatal.ruleName,
        message: fatal.userMessage,
      ));
      if (!mounted) return;
      state = GetMapsError(
        ShapefileValidationFailure(fatal.userMessage, ruleName: fatal.ruleName),
        isRetryable: false,
      );
      return;
    }

    if (report.hasWarnings) {
      if (!mounted) return;
      state = ShapefileWarning(
        warnings: report.warnings.map((w) => w.userMessage).toList(),
        pendingFiles: shapefiles,
        expectedMd5s: shapeMd5s,
      );
      return;
    }

    await _doImport(selected, shapefiles);
  }

  Future<void> _doImport(
    DriveAssignment selected,
    Map<String, Uint8List> files,
  ) async {
    if (!mounted) return;
    state = const ImportingShapefiles();
    try {
      await shapefileImporter.importShapefiles(
        files,
        selected.assignmentId,
        selected.inputZipModifiedTime,
        selected.driveFolderId,
        _enumeratorId ?? '',
      );
    } catch (e) {
      if (!mounted) return;
      state = GetMapsError(StorageFailure(e.toString()));
      return;
    }
    await _startTileDownload();
  }

  Future<void> _startTileDownload() async {
    if (!mounted) return;
    final assignment = await assignmentRepo.getCurrentAssignment();
    if (!mounted) return;
    if (assignment == null) {
      state = const GetMapsError(
          StorageFailure('Assignment not found after import'));
      return;
    }

    final packId = const Uuid().v4();
    await packRepo.upsert(
      id: packId,
      assignmentId: assignment.id,
      regionBoundsGeojson: assignment.boundaryPolygonGeojson,
    );

    if (!mounted) return;
    state = const DownloadingTiles(downloadedBytes: 0, totalBytes: 0);

    final stream = packAdapter.createPack(
      regionGeojson: assignment.boundaryPolygonGeojson,
      styleUri: _styleUri,
      minZoom: _minZoom,
      maxZoom: _maxZoom,
    );

    try {
      await for (final event in stream) {
        if (!mounted) return;
        switch (event) {
          case OfflinePackProgress(:final downloaded, :final total):
            state = DownloadingTiles(downloadedBytes: downloaded, totalBytes: total);
            await packRepo.updateProgress(packId, downloaded, total);
          case OfflinePackComplete():
            await packRepo.markReady(packId);
            final features = await featureRepo
                .watchFeaturesForAssignment(assignment.id)
                .first;
            final currentTotal = state is DownloadingTiles
                ? (state as DownloadingTiles).totalBytes
                : 0;
            state = Ready(featureCount: features.length, totalBytes: currentTotal);
            return;
          case OfflinePackError(:final message):
            await packRepo.markError(packId, message);
            state = GetMapsError(StorageFailure(message));
            return;
        }
      }
    } on Object catch (e) {
      if (!mounted) return;
      state = GetMapsError(StorageFailure(e.toString()));
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    await packAdapter.cancelAllPacks();
    if (!mounted) return;
    state = const Cancelled();
  }

  void reset() {
    _cancelled = false;
    state = const Idle();
  }
}

// ── providers ────────────────────────────────────────────────────────────────

final shapefileValidatorProvider = Provider<ShapefileValidator>((ref) {
  return ShapefileValidator();
});

/// Overridden in main.dart with SupabaseValidationFailureReporter.
final validationFailureReporterProvider =
    Provider<ValidationFailureReporter>((ref) {
  throw UnimplementedError(
      'Override validationFailureReporterProvider in main.dart');
});

final getMapsNotifierProvider =
    StateNotifierProvider<GetMapsNotifier, GetMapsState>((ref) {
  return GetMapsNotifier(
    assignmentRepo: ref.watch(assignmentRepositoryProvider),
    packRepo: ref.watch(offlineTilePackRepositoryProvider),
    packAdapter: ref.watch(offlinePackAdapterProvider),
    featureRepo: ref.watch(featureRepositoryProvider),
    driveApi: ref.watch(driveApiProvider),
    googleAuthRepo: ref.watch(googleAuthRepositoryProvider),
    shapefileImporter: ref.watch(shapefileImporterProvider),
    storageChecker: ref.watch(storageCheckerProvider),
    validator: ref.watch(shapefileValidatorProvider),
    reporter: ref.watch(validationFailureReporterProvider),
  );
});

final currentAssignmentProvider = StreamProvider<Assignment?>((ref) {
  return ref.watch(assignmentRepositoryProvider).watchCurrentAssignment();
});
```

Add the missing imports at the top of `assignment_providers.dart`:
```dart
import 'dart:async';
import 'package:firecheck/core/sync/shapefile/shapefile_validator.dart';
import 'package:firecheck/core/validation/validation_failure_reporter.dart';
```

- [ ] **Step 4: Run the new notifier tests — expect pass**

```bash
flutter test test/features/assignment/get_maps_notifier_test.dart
```
Expected: All tests pass, including the 4 new US-19 tests.

- [ ] **Step 5: Run all tests**

```bash
flutter test
```
Expected: All pass. (The screen will have compile errors if it hasn't been updated yet — see Task 16.)

- [ ] **Step 6: Commit**

```bash
git add lib/features/assignment/presentation/assignment_providers.dart \
  test/features/assignment/get_maps_notifier_test.dart
git commit -m "feat(notifier): add validation phase, ValidatingShapefiles state, soft-warning path, retryDownload"
```

---

## Task 15: Add l10n keys

**Files:**
- Modify: `lib/core/i18n/app_en.arb`

- [ ] **Step 1: Add new keys**

In `lib/core/i18n/app_en.arb`, append the following entries before the closing `}`. Place them after the existing `getMaps*` entries for grouping:

```json
  "getMapsChecksumError": "The map file was damaged during download.",
  "getMapsIncompleteFilesError": "Map files are missing or incomplete.",
  "getMapsHeaderError": "Map geometry file is corrupted.",
  "getMapsIndexError": "Map index is inconsistent with geometry.",
  "getMapsAttributeError": "Map attribute table is corrupted or mismatched.",
  "getMapsGeometryError": "Map contains no usable features.",
  "getMapsCrsError": "Map uses an unsupported coordinate system.",
  "getMapsContactSupervisor": "Contact your supervisor to request a corrected file.",
  "getMapsValidating": "Checking map files…",
  "getMapsWarningTitle": "This assignment has minor issues",
  "getMapsWarningBody": "{warnings}",
  "@getMapsWarningBody": {
    "placeholders": {
      "warnings": { "type": "String" }
    }
  },
  "getMapsWarningContinue": "Continue anyway",
  "getMapsClose": "Close"
```

- [ ] **Step 2: Regenerate l10n**

```bash
flutter gen-l10n
```
Expected: `lib/generated/l10n/app_localizations.dart` updates without errors.

- [ ] **Step 3: Commit**

```bash
git add lib/core/i18n/app_en.arb lib/generated/
git commit -m "feat(l10n): add shapefile validation error and warning keys"
```

---

## Task 16: Update get_maps_screen.dart

**Files:**
- Modify: `lib/features/assignment/presentation/get_maps_screen.dart`

- [ ] **Step 1: Add new state cases to the switch and update _ErrorView**

In the `build` method's `switch (state)`, add cases for the two new states and update `GetMapsError`:

Replace:
```dart
          GetMapsError(:final failure) => _ErrorView(
              failure: failure,
              onRetry: () {
                ref.read(getMapsNotifierProvider.notifier).reset();
                ref.read(getMapsNotifierProvider.notifier).start();
              },
            ),
```
With:
```dart
          ValidatingShapefiles() => const _ValidatingView(),
          ShapefileWarning() => _ShapefileWarningView(state: state as ShapefileWarning),
          GetMapsError(:final failure, :final isRetryable) => _ErrorView(
              failure: failure,
              isRetryable: isRetryable,
              onAction: isRetryable
                  ? () => ref.read(getMapsNotifierProvider.notifier).retryDownload()
                  : () => ref.read(getMapsNotifierProvider.notifier).reset(),
            ),
```

- [ ] **Step 2: Add _ValidatingView widget**

Append to the bottom of the file:
```dart
class _ValidatingView extends StatelessWidget {
  const _ValidatingView();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(l.getMapsValidating, textAlign: TextAlign.center),
      ],
    );
  }
}
```

- [ ] **Step 3: Add _ShapefileWarningView widget**

```dart
class _ShapefileWarningView extends ConsumerWidget {
  const _ShapefileWarningView({required this.state});
  final ShapefileWarning state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.warning_amber_rounded,
            size: 48, color: Theme.of(context).colorScheme.tertiary),
        const SizedBox(height: 12),
        Text(
          l.getMapsWarningTitle,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        ...state.warnings.map(
          (w) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(w, textAlign: TextAlign.center),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () =>
              ref.read(getMapsNotifierProvider.notifier).acknowledgeWarning(),
          child: Text(l.getMapsWarningContinue),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => ref.read(getMapsNotifierProvider.notifier).reset(),
          child: Text(l.getMapsClose),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Update _ErrorView**

Replace the existing `_ErrorView` class:
```dart
class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.failure,
    required this.isRetryable,
    required this.onAction,
  });
  final Failure failure;
  final bool isRetryable;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final isValidation = failure is ShapefileValidationFailure;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 64),
        const SizedBox(height: 12),
        Text(
          '${l.downloadFailed} ${failure.message}',
          textAlign: TextAlign.center,
        ),
        if (isValidation) ...[
          const SizedBox(height: 8),
          Text(
            l.getMapsContactSupervisor,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: onAction,
          child: Text(isRetryable ? l.retryButton : l.getMapsClose),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.backToHome),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Run all tests**

```bash
flutter test
```
Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add lib/features/assignment/presentation/get_maps_screen.dart
git commit -m "feat(ui): add ValidatingShapefiles + ShapefileWarning screens; update error view for isRetryable"
```

---

## Task 17: Wire DI in main.dart

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Add import for reporter + validator**

At the top of `lib/main.dart`, add:
```dart
import 'package:firecheck/core/validation/supabase_validation_failure_reporter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
```
(supabase_flutter is already imported — check and skip if duplicate.)

- [ ] **Step 2: Remove `validator` from shapefileImporterProvider override**

Find in `lib/main.dart` (around lines 88–95):
```dart
        shapefileImporterProvider.overrideWith(
          (ref) => ShapefileImporter(
            db: ref.watch(appDatabaseProvider),
            validator: const ShapefileValidator(),
            dbfParser: const DbfParser(),
            reprojector: Reprojector(),
          ),
        ),
```
Change to:
```dart
        shapefileImporterProvider.overrideWith(
          (ref) => ShapefileImporter(
            db: ref.watch(appDatabaseProvider),
            dbfParser: const DbfParser(),
            reprojector: Reprojector(),
          ),
        ),
```

Also remove the import for `ShapefileValidator` from main.dart if it is no longer referenced.

- [ ] **Step 3: Add validationFailureReporterProvider override**

After the `storageCheckerProvider.overrideWithValue(...)` line, add:
```dart
        validationFailureReporterProvider.overrideWithValue(
          SupabaseValidationFailureReporter(
            supabase: Supabase.instance.client,
          ),
        ),
```

- [ ] **Step 4: Final full test run**

```bash
flutter test
```
Expected: All tests pass.

- [ ] **Step 5: Final commit**

```bash
git add lib/main.dart
git commit -m "feat(di): wire SupabaseValidationFailureReporter; remove validator from ShapefileImporter override"
```

---

## Self-Review

**Spec coverage check:**

| Requirement | Task |
|---|---|
| Validate before marking available offline | Tasks 9, 14 |
| Block download on fatal | Task 14 (_downloadAndValidate) |
| Plain-language error message | Tasks 11, 15, 16 |
| Log with assignmentId, enumeratorId, timestamp, checksum, rule | Tasks 11, 14 |
| Supervisor notification (Supabase insert) | Task 11 (SupabaseValidationFailureReporter) |
| Retry on transient failure | Tasks 13, 14, 16 |
| Soft-warning path | Tasks 13, 14, 15, 16 |
| Checksum rule | Tasks 1, 2 |
| File-set completeness | Task 3 |
| Header integrity | Task 4 |
| Index consistency | Task 5 |
| Attribute integrity | Task 6 |
| Geometry sanity | Task 7 |
| Projection check | Task 8 |
| Orchestrator (fail-fast, warning accumulation) | Task 9 |
| Unit tests with known-bad fixture per rule | Tasks 2–8 |

**Type consistency check:** `ShapefileValidator.validate(files, expectedMd5s)` — used in notifier (Task 14) matches signature defined in Task 9. `DriveDownloadComplete(files, expectedMd5s)` — defined Task 10, consumed Task 14. `ShapefileValidationFailure(message, ruleName: name)` — defined Task 11, constructed Task 14. `ValidationReport.fatal`, `.warnings`, `.hasFatals`, `.hasWarnings`, `.isClean` — defined Task 1, used Tasks 9 and 14. All consistent.

**Placeholder scan:** No TBDs. All code blocks are complete. ✓
