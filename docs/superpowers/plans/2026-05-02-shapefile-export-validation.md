# Shapefile Export Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gate the Export Shapefile share action behind a two-phase validation: (1) a DB-level check that every layer has complete, exportable features, and (2) a post-export sanity check that the generated archive entries are non-empty.

**Architecture:** A new `ShapefileExportValidator` queries the Drift DB before the export fires, and two new states (`ExportValidating`, `ExportValidationFailed`) are added to the existing state machine. If validation passes, `ShapefileExporter` runs as normal, followed by a lightweight sanity check on the generated layer outputs before they are packed into the ZIP. Validation errors render as a persistent inline list below the export tile on `HomeScreen`; the existing `ExportFailed` snackbar path is unchanged.

**Tech Stack:** Flutter, Dart, Drift (SQLite ORM), Riverpod (`StateNotifier`), `flutter_test`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `lib/core/sync/shapefile/export/export_validation_result.dart` | `ExportLayer`, `ExportLayerIssue`, `ExportLayerError`, `ExportValidationResult` value objects |
| Create | `lib/core/sync/shapefile/export/shapefile_export_validator.dart` | DB validation logic — empty-layer check + orphan check |
| Create | `test/core/sync/shapefile/export/shapefile_export_validator_test.dart` | 6 validator unit tests |
| Modify | `lib/features/home/domain/export_state.dart` | Add `ExportValidating`, `ExportValidationFailed` |
| Modify | `lib/core/sync/shapefile/export/shapefile_exporter.dart` | Post-export sanity check after `compute()` |
| Modify | `test/core/sync/shapefile/export/shapefile_exporter_test.dart` | Add sanity-check integration test |
| Modify | `lib/features/home/data/shapefile_export_notifier.dart` | Accept `ShapefileExportValidator`; new state transitions |
| Modify | `test/features/home/shapefile_export_notifier_test.dart` | Update existing tests + add 2 new state-machine tests |
| Modify | `lib/core/i18n/app_en.arb` | 5 new l10n keys |
| Modify | `lib/core/i18n/app_tl.arb` | 5 matching Tagalog keys |
| Modify | `lib/features/home/presentation/home_screen.dart` | Inline error list for `ExportValidationFailed`; `isBusy` guard |

---

### Task 1: Create ExportValidationResult model

**Files:**
- Create: `lib/core/sync/shapefile/export/export_validation_result.dart`

- [ ] **Step 1: Create the file**

```dart
// lib/core/sync/shapefile/export/export_validation_result.dart

enum ExportLayer { buildings, roads }

enum ExportLayerIssue { emptyLayer, missingRequiredFields }

class ExportLayerError {
  const ExportLayerError({required this.layer, required this.issue});
  final ExportLayer layer;
  final ExportLayerIssue issue;
}

class ExportValidationResult {
  const ExportValidationResult({required this.errors});
  final List<ExportLayerError> errors;
  bool get isValid => errors.isEmpty;
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/core/sync/shapefile/export/export_validation_result.dart`

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck"
git add lib/core/sync/shapefile/export/export_validation_result.dart
git commit -m "feat(export-validation): add ExportValidationResult model"
```

---

### Task 2: ShapefileExportValidator (TDD)

**Files:**
- Create: `test/core/sync/shapefile/export/shapefile_export_validator_test.dart`
- Create: `lib/core/sync/shapefile/export/shapefile_export_validator.dart`

- [ ] **Step 1: Write the failing test file**

Create `test/core/sync/shapefile/export/shapefile_export_validator_test.dart`:

```dart
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/shapefile/export/export_validation_result.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_export_validator.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _seedBuilding(
  AppDatabase db, {
  required String assignmentId,
  required String featureId,
  required String submissionId,
}) async {
  final geoJson = jsonEncode({
    'type': 'Polygon',
    'coordinates': [
      [
        [120.0, 14.0], [121.0, 14.0], [121.0, 15.0],
        [120.0, 15.0], [120.0, 14.0],
      ],
    ],
  });
  await db.into(db.features).insert(FeaturesCompanion.insert(
    id: featureId,
    assignmentId: assignmentId,
    featureType: 'building',
    geometryGeojson: geoJson,
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
  await db.into(db.buildingAttributes).insert(
    BuildingAttributesCompanion.insert(
      submissionId: submissionId,
      fireFightingFacilitiesJson: const Value('[]'),
      fireLoadJson: const Value('[]'),
    ),
  );
}

// Complete building feature WITHOUT a buildingAttributes row.
// Simulates a feature that would be silently excluded by the exporter's inner join.
Future<void> _seedOrphanBuilding(
  AppDatabase db, {
  required String assignmentId,
  required String featureId,
  required String submissionId,
}) async {
  final geoJson = jsonEncode({
    'type': 'Polygon',
    'coordinates': [
      [
        [120.0, 14.0], [121.0, 14.0], [121.0, 15.0],
        [120.0, 15.0], [120.0, 14.0],
      ],
    ],
  });
  await db.into(db.features).insert(FeaturesCompanion.insert(
    id: featureId,
    assignmentId: assignmentId,
    featureType: 'building',
    geometryGeojson: geoJson,
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
  // Intentionally no buildingAttributes row
}

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
  await db.into(db.roadAttributes).insert(
    RoadAttributesCompanion.insert(
      submissionId: submissionId,
      roadFeaturesJson: const Value('[]'),
    ),
  );
}

// Complete road feature WITHOUT a roadAttributes row.
Future<void> _seedOrphanRoad(
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
  // Intentionally no roadAttributes row
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  ShapefileExportValidator makeValidator() =>
      ShapefileExportValidator(db: db);

  test('buildings layer empty → isValid false, buildings/emptyLayer error',
      () async {
    await _seedRoad(
        db, assignmentId: 'a1', featureId: 'r1', submissionId: 'sr1');
    final result = await makeValidator().validate('a1');
    expect(result.isValid, isFalse);
    expect(result.errors, hasLength(1));
    expect(result.errors.first.layer, ExportLayer.buildings);
    expect(result.errors.first.issue, ExportLayerIssue.emptyLayer);
  });

  test('roads layer empty → isValid false, roads/emptyLayer error', () async {
    await _seedBuilding(
        db, assignmentId: 'a1', featureId: 'b1', submissionId: 'sb1');
    final result = await makeValidator().validate('a1');
    expect(result.isValid, isFalse);
    expect(result.errors, hasLength(1));
    expect(result.errors.first.layer, ExportLayer.roads);
    expect(result.errors.first.issue, ExportLayerIssue.emptyLayer);
  });

  test('both layers empty → isValid false, two emptyLayer errors', () async {
    final result = await makeValidator().validate('a1');
    expect(result.isValid, isFalse);
    expect(result.errors, hasLength(2));
    expect(
      result.errors.map((e) => e.issue),
      everyElement(ExportLayerIssue.emptyLayer),
    );
  });

  test('building orphan → isValid false, buildings/missingRequiredFields',
      () async {
    await _seedOrphanBuilding(
        db, assignmentId: 'a1', featureId: 'b1', submissionId: 'sb1');
    await _seedRoad(
        db, assignmentId: 'a1', featureId: 'r1', submissionId: 'sr1');
    final result = await makeValidator().validate('a1');
    expect(result.isValid, isFalse);
    expect(result.errors, hasLength(1));
    expect(result.errors.first.layer, ExportLayer.buildings);
    expect(result.errors.first.issue, ExportLayerIssue.missingRequiredFields);
  });

  test('road orphan → isValid false, roads/missingRequiredFields', () async {
    await _seedBuilding(
        db, assignmentId: 'a1', featureId: 'b1', submissionId: 'sb1');
    await _seedOrphanRoad(
        db, assignmentId: 'a1', featureId: 'r1', submissionId: 'sr1');
    final result = await makeValidator().validate('a1');
    expect(result.isValid, isFalse);
    expect(result.errors, hasLength(1));
    expect(result.errors.first.layer, ExportLayer.roads);
    expect(result.errors.first.issue, ExportLayerIssue.missingRequiredFields);
  });

  test('all layers complete and valid → isValid true, no errors', () async {
    await _seedBuilding(
        db, assignmentId: 'a1', featureId: 'b1', submissionId: 'sb1');
    await _seedRoad(
        db, assignmentId: 'a1', featureId: 'r1', submissionId: 'sr1');
    final result = await makeValidator().validate('a1');
    expect(result.isValid, isTrue);
    expect(result.errors, isEmpty);
  });
}
```

- [ ] **Step 2: Run to confirm compilation fails**

Run: `cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/shapefile/export/shapefile_export_validator_test.dart`

Expected: Compilation error — `shapefile_export_validator.dart` not found yet.

- [ ] **Step 3: Implement ShapefileExportValidator**

Create `lib/core/sync/shapefile/export/shapefile_export_validator.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/shapefile/export/export_validation_result.dart';

class ShapefileExportValidator {
  const ShapefileExportValidator({required this.db});
  final AppDatabase db;

  Future<ExportValidationResult> validate(String assignmentId) async {
    final errors = <ExportLayerError>[];

    for (final layer in ExportLayer.values) {
      final featureType =
          layer == ExportLayer.buildings ? 'building' : 'road';

      final totalComplete = await _countComplete(assignmentId, featureType);
      if (totalComplete == 0) {
        errors.add(
          ExportLayerError(layer: layer, issue: ExportLayerIssue.emptyLayer),
        );
        continue;
      }

      final exportable =
          await _countExportable(assignmentId, featureType, layer);
      if (exportable < totalComplete) {
        errors.add(
          ExportLayerError(
            layer: layer,
            issue: ExportLayerIssue.missingRequiredFields,
          ),
        );
      }
    }

    return ExportValidationResult(errors: errors);
  }

  Future<int> _countComplete(
      String assignmentId, String featureType) async {
    final rows = await (db.select(db.features)
          ..where(
            (f) =>
                f.assignmentId.equals(assignmentId) &
                f.featureType.equals(featureType) &
                f.status.equals('complete'),
          ))
        .get();
    return rows.length;
  }

  Future<int> _countExportable(
    String assignmentId,
    String featureType,
    ExportLayer layer,
  ) async {
    if (layer == ExportLayer.buildings) {
      return (await (db.select(db.features).join([
        innerJoin(
          db.submissions,
          db.submissions.featureId.equalsExp(db.features.id),
        ),
        innerJoin(
          db.buildingAttributes,
          db.buildingAttributes.submissionId.equalsExp(db.submissions.id),
        ),
      ])
                ..where(
                  db.features.assignmentId.equals(assignmentId) &
                      db.features.featureType.equals(featureType) &
                      db.features.status.equals('complete'),
                ))
              .get())
          .length;
    } else {
      return (await (db.select(db.features).join([
        innerJoin(
          db.submissions,
          db.submissions.featureId.equalsExp(db.features.id),
        ),
        innerJoin(
          db.roadAttributes,
          db.roadAttributes.submissionId.equalsExp(db.submissions.id),
        ),
      ])
                ..where(
                  db.features.assignmentId.equals(assignmentId) &
                      db.features.featureType.equals(featureType) &
                      db.features.status.equals('complete'),
                ))
              .get())
          .length;
    }
  }
}
```

- [ ] **Step 4: Run tests to confirm all 6 pass**

Run: `cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/shapefile/export/shapefile_export_validator_test.dart`

Expected: `+6: All tests passed!`

- [ ] **Step 5: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck"
git add lib/core/sync/shapefile/export/shapefile_export_validator.dart \
        test/core/sync/shapefile/export/shapefile_export_validator_test.dart
git commit -m "feat(export-validation): add ShapefileExportValidator with 6 tests"
```

---

### Task 3: Extend ExportState with validation variants

**Files:**
- Modify: `lib/features/home/domain/export_state.dart`

- [ ] **Step 1: Replace file contents**

```dart
// lib/features/home/domain/export_state.dart
import 'package:firecheck/core/sync/shapefile/export/export_failure.dart';
import 'package:firecheck/core/sync/shapefile/export/export_validation_result.dart';

sealed class ExportState {
  const ExportState();
}

class ExportIdle extends ExportState {
  const ExportIdle();
}

class ExportValidating extends ExportState {
  const ExportValidating();
}

class ExportValidationFailed extends ExportState {
  const ExportValidationFailed(this.errors);
  final List<ExportLayerError> errors;
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

- [ ] **Step 2: Verify it compiles**

Run: `cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze lib/features/home/domain/export_state.dart`

Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck"
git add lib/features/home/domain/export_state.dart
git commit -m "feat(export-validation): add ExportValidating and ExportValidationFailed states"
```

---

### Task 4: Post-export sanity check in ShapefileExporter

**Files:**
- Modify: `lib/core/sync/shapefile/export/shapefile_exporter.dart`
- Modify: `test/core/sync/shapefile/export/shapefile_exporter_test.dart`

- [ ] **Step 1: Add the sanity-check integration test**

In `test/core/sync/shapefile/export/shapefile_exporter_test.dart`, add this test inside `void main()` after the existing 5 tests:

```dart
  test('exported archive entries are non-empty for all required layer files',
      () async {
    const assignmentId = 'sanity-check-001';
    await _seedBuilding(db,
        assignmentId: assignmentId, featureId: 'b1', submissionId: 'sb1');
    await _seedRoad(db,
        assignmentId: assignmentId, featureId: 'r1', submissionId: 'sr1');

    final capturedPaths = <String>[];
    await makeExporter(capturedPaths: capturedPaths)
        .export(assignmentId: assignmentId);

    final zipBytes = await File(capturedPaths.first).readAsBytes();
    final archive = ZipDecoder().decodeBytes(zipBytes);

    for (final ext in ['.shp', '.shx', '.dbf']) {
      expect(
        archive.files.firstWhere((f) => f.name == 'buildings$ext').size,
        greaterThan(0),
        reason: 'buildings$ext must not be empty',
      );
      expect(
        archive.files.firstWhere((f) => f.name == 'roads$ext').size,
        greaterThan(0),
        reason: 'roads$ext must not be empty',
      );
    }
  });
```

- [ ] **Step 2: Run new test to confirm it passes with current code (positive-path baseline)**

Run: `cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/shapefile/export/shapefile_exporter_test.dart --name "exported archive entries"`

Expected: `+1: All tests passed!`

- [ ] **Step 3: Add the sanity check to ShapefileExporter.export()**

In `lib/core/sync/shapefile/export/shapefile_exporter.dart`, locate the `try { outputs = await Future.wait(...) }` block. Add the sanity check immediately after it, before the `// Build ZIP archive` comment:

```dart
    // Write each layer via compute
    List<_LayerOutput> outputs;
    try {
      outputs = await Future.wait(
        inputs.map((input) => compute(_writeLayer, input)),
      );
    } catch (e) {
      return WriteError(e.toString());
    }

    // Guard against exporter bugs producing empty file components.
    for (final out in outputs) {
      if (out.shp.isEmpty || out.shx.isEmpty || out.dbf.isEmpty) {
        return WriteError('Layer ${out.layerName} produced empty components');
      }
    }

    // Build ZIP archive
    final archive = Archive();
```

- [ ] **Step 4: Run all exporter tests**

Run: `cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/core/sync/shapefile/export/shapefile_exporter_test.dart`

Expected: `+6: All tests passed!`

- [ ] **Step 5: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck"
git add lib/core/sync/shapefile/export/shapefile_exporter.dart \
        test/core/sync/shapefile/export/shapefile_exporter_test.dart
git commit -m "feat(export-validation): add post-export sanity check to ShapefileExporter"
```

---

### Task 5: Update ShapefileExportNotifier

**Files:**
- Modify: `lib/features/home/data/shapefile_export_notifier.dart`
- Modify: `test/features/home/shapefile_export_notifier_test.dart`

- [ ] **Step 1: Write the updated test file**

Replace the full contents of `test/features/home/shapefile_export_notifier_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_export_validator.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_exporter.dart';
import 'package:firecheck/features/home/data/shapefile_export_notifier.dart';
import 'package:firecheck/features/home/domain/export_state.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _seedBuilding(
  AppDatabase db, {
  required String assignmentId,
  required String featureId,
  required String submissionId,
}) async {
  final geoJson = jsonEncode({
    'type': 'Polygon',
    'coordinates': [
      [
        [120.0, 14.0], [121.0, 14.0], [121.0, 15.0],
        [120.0, 15.0], [120.0, 14.0],
      ],
    ],
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
    syncStatus: const Value('ready_to_upload'),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  ));
  await db.into(db.buildingAttributes).insert(
    BuildingAttributesCompanion.insert(
      submissionId: submissionId,
      cbmsId: const Value('C001'),
      buildingName: const Value('Test Hall'),
      ra9514Type: const Value('Group E'),
      storeys: const Value(3),
      material: const Value('Concrete'),
      costAmount: const Value(500000),
      fireFightingFacilitiesJson: const Value('["sprinkler","extinguisher"]'),
      fireLoadJson: const Value('["paper","chemicals"]'),
    ),
  );
}

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
  await db.into(db.roadAttributes).insert(
    RoadAttributesCompanion.insert(
      submissionId: submissionId,
      roadName: const Value('Main St'),
      widthMeters: const Value(8),
      roadFeaturesJson: const Value('["Pedestrian"]'),
    ),
  );
}

ShapefileExportNotifier makeNotifier({
  required String assignmentId,
  required AppDatabase db,
  List<String>? capturedPaths,
  ShapefileExportValidator? validator,
}) {
  final exporter = ShapefileExporter(
    db: db,
    shareFile: (path) async { capturedPaths?.add(path); },
    tempDirOverride: Directory.systemTemp.createTempSync('notifier_test_'),
  );
  return ShapefileExportNotifier(
    assignmentId: assignmentId,
    exporter: exporter,
    validator: validator ?? ShapefileExportValidator(db: db),
  );
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('initial state is ExportIdle', () {
    final notifier = makeNotifier(assignmentId: 'a1', db: db);
    expect(notifier.state, isA<ExportIdle>());
  });

  test('empty DB → Validating then ValidationFailed then Idle', () async {
    final notifier = makeNotifier(assignmentId: 'a1', db: db);
    final states = <ExportState>[];
    notifier.addListener(states.add, fireImmediately: false);

    await notifier.export();

    expect(states, [
      isA<ExportValidating>(),
      isA<ExportValidationFailed>(),
      isA<ExportIdle>(),
    ]);
    expect((states[1] as ExportValidationFailed).errors, isNotEmpty);
  });

  test('tapping export while Validating or Exporting is a no-op', () async {
    final notifier = makeNotifier(assignmentId: 'a1', db: db);
    final states = <ExportState>[];
    notifier.addListener(states.add, fireImmediately: false);

    final first = notifier.export();
    final second = notifier.export();
    await Future.wait([first, second]);

    expect(states.whereType<ExportValidating>(), hasLength(1));
  });

  test('after ValidationFailed, notifier resets to Idle', () async {
    final notifier = makeNotifier(assignmentId: 'a1', db: db);
    await notifier.export();
    expect(notifier.state, isA<ExportIdle>());
  });

  test('validation pass → Validating then Exporting then Done then Idle',
      () async {
    const assignmentId = 'a-success';
    await _seedBuilding(
        db, assignmentId: assignmentId, featureId: 'b1', submissionId: 'sb1');
    await _seedRoad(
        db, assignmentId: assignmentId, featureId: 'r1', submissionId: 'sr1');

    final notifier = makeNotifier(assignmentId: assignmentId, db: db);
    final states = <ExportState>[];
    notifier.addListener(states.add, fireImmediately: false);

    await notifier.export();

    expect(states, [
      isA<ExportValidating>(),
      isA<ExportExporting>(),
      isA<ExportDone>(),
      isA<ExportIdle>(),
    ]);
  });

  test('after successful export, notifier resets to Idle', () async {
    const assignmentId = 'a-success-2';
    await _seedBuilding(
        db, assignmentId: assignmentId, featureId: 'b1', submissionId: 'sb1');
    await _seedRoad(
        db, assignmentId: assignmentId, featureId: 'r1', submissionId: 'sr1');

    final notifier = makeNotifier(assignmentId: assignmentId, db: db);
    await notifier.export();

    expect(notifier.state, isA<ExportIdle>());
  });
}
```

- [ ] **Step 2: Run to confirm compilation fails**

Run: `cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/home/shapefile_export_notifier_test.dart`

Expected: Compilation error — `ShapefileExportNotifier` constructor does not yet accept `validator`.

- [ ] **Step 3: Update ShapefileExportNotifier**

Replace the full contents of `lib/features/home/data/shapefile_export_notifier.dart`:

```dart
import 'package:firecheck/core/sync/shapefile/export/export_validation_result.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_export_validator.dart';
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
    required ShapefileExportValidator validator,
  })  : _assignmentId = assignmentId,
        _exporter = exporter,
        _validator = validator,
        super(const ExportIdle());

  final String _assignmentId;
  final ShapefileExporter _exporter;
  final ShapefileExportValidator _validator;

  Future<void> export() async {
    if (state is ExportValidating || state is ExportExporting) return;

    state = const ExportValidating();
    final result = await _validator.validate(_assignmentId);

    if (!mounted) return;
    if (!result.isValid) {
      state = ExportValidationFailed(result.errors);
      state = const ExportIdle();
      return;
    }

    state = const ExportExporting();
    final failure = await _exporter.export(assignmentId: _assignmentId);

    if (!mounted) return;
    if (failure != null) {
      state = ExportFailed(failure);
      state = const ExportIdle();
      return;
    }

    state = const ExportDone();
    state = const ExportIdle();
  }
}

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
    validator: ShapefileExportValidator(db: db),
  );
});
```

- [ ] **Step 4: Run tests to confirm all 6 pass**

Run: `cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test test/features/home/shapefile_export_notifier_test.dart`

Expected: `+6: All tests passed!`

- [ ] **Step 5: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck"
git add lib/features/home/data/shapefile_export_notifier.dart \
        test/features/home/shapefile_export_notifier_test.dart
git commit -m "feat(export-validation): wire ShapefileExportValidator into ShapefileExportNotifier"
```

---

### Task 6: L10n keys + HomeScreen inline validation errors

**Files:**
- Modify: `lib/core/i18n/app_en.arb`
- Modify: `lib/core/i18n/app_tl.arb`
- Modify: `lib/features/home/presentation/home_screen.dart`

- [ ] **Step 1: Add new keys to app_en.arb**

In `lib/core/i18n/app_en.arb`, replace the final `}` with these entries followed by a new closing `}`:

```json
  "exportValidating": "Validating…",
  "exportValidationBuildingsEmpty": "No buildings recorded. Survey at least one building before exporting.",
  "exportValidationRoadsEmpty": "No roads recorded. Survey at least one road before exporting.",
  "exportValidationBuildingsMissingFields": "Some building entries are missing required fields. Complete all building forms before exporting.",
  "exportValidationRoadsMissingFields": "Some road entries are missing required fields. Complete all road forms before exporting."
}
```

- [ ] **Step 2: Add matching keys to app_tl.arb**

In `lib/core/i18n/app_tl.arb`, replace the final `}` with these entries followed by a new closing `}`. (Provide Tagalog translations below; English is used as placeholder — replace with native translations before release.)

```json
  "exportValidating": "Bine-validate…",
  "exportValidationBuildingsEmpty": "Walang naitalagang gusali. Mag-survey ng kahit isang gusali bago mag-export.",
  "exportValidationRoadsEmpty": "Walang naitalagang kalsada. Mag-survey ng kahit isang kalsada bago mag-export.",
  "exportValidationBuildingsMissingFields": "May ilang gusali na may kulang na impormasyon. Kumpletuhin ang lahat ng form ng gusali bago mag-export.",
  "exportValidationRoadsMissingFields": "May ilang kalsada na may kulang na impormasyon. Kumpletuhin ang lahat ng form ng kalsada bago mag-export."
}
```

- [ ] **Step 3: Run gen-l10n**

Run: `cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter gen-l10n`

Expected: No errors. Confirm the new keys appear in `lib/generated/l10n/app_localizations_en.dart`:
```bash
grep -l "exportValidating\|exportValidationBuildings" lib/generated/l10n/app_localizations_en.dart
```
Expected: the file is listed.

- [ ] **Step 4: Update HomeScreen**

Replace the full contents of `lib/features/home/presentation/home_screen.dart`:

```dart
import 'package:firecheck/core/security/biometric_gate_provider.dart';
import 'package:firecheck/core/sync/shapefile/export/export_failure.dart';
import 'package:firecheck/core/sync/shapefile/export/export_validation_result.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/submitted_banner.dart';
import 'package:firecheck/features/home/data/shapefile_export_notifier.dart';
import 'package:firecheck/features/home/domain/export_state.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final asyncSnap = ref.watch(progressProvider);
    final lock = ref.watch(assignmentLockStateProvider).value;
    final isLocked = lock is Submitted || lock is ClosedRemotely;
    final exportState = ref.watch(shapefileExportNotifierProvider);
    final isBusy =
        exportState is ExportValidating || exportState is ExportExporting;

    ref.listen<ExportState>(shapefileExportNotifierProvider, (prev, next) {
      if (next is ExportFailed) {
        final msg = switch (next.failure) {
          NoCompletedFeatures() => l.exportErrorNoFeatures,
          WriteError()          => l.exportErrorWriteFailed,
          ShareError()          => l.exportErrorShareFailed,
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('FireCheck')),
      body: asyncSnap.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (snap) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (lock is Submitted)
                SubmittedBanner(submittedAt: lock.submittedAt)
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.assignmentProgress,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l.featuresLabel(
                            snap.completedFeatures,
                            snap.totalFeatures,
                          ),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        LinearProgressIndicator(
                          value: snap.totalFeatures == 0
                              ? 0
                              : snap.completedFeatures / snap.totalFeatures,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l.jobCountsLabel(
                            snap.queuedJobs,
                            snap.failedJobs,
                            snap.deadJobs,
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              _ActionTile(
                title: l.gatherData,
                subtitle: l.gatherDataSubtitle,
                onTap: () => context.go('/map'),
              ),
              _ActionTile(
                title: l.getMaps,
                subtitle: l.getMapsSubtitle,
                onTap: () => context.go('/get-maps'),
              ),
              if (!isLocked)
                _ActionTile(
                  title: l.uploadData,
                  subtitle: l.uploadDataSubtitle,
                  onTap: () => _onUploadDataTap(context, ref, l),
                ),
              _ActionTile(
                title: switch (exportState) {
                  ExportValidating() => l.exportValidating,
                  ExportExporting() => l.exportShapefileExporting,
                  _ => l.exportShapefile,
                },
                subtitle: l.exportShapefileSubtitle,
                trailing: isBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: (snap.completedFeatures == 0 || isBusy)
                    ? null
                    : () => ref
                        .read(shapefileExportNotifierProvider.notifier)
                        .export(),
              ),
              if (exportState is ExportValidationFailed)
                ...exportState.errors.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 14,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _validationErrorMessage(l, e),
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _validationErrorMessage(AppLocalizations l, ExportLayerError e) =>
      switch ((e.layer, e.issue)) {
        (ExportLayer.buildings, ExportLayerIssue.emptyLayer) =>
          l.exportValidationBuildingsEmpty,
        (ExportLayer.roads, ExportLayerIssue.emptyLayer) =>
          l.exportValidationRoadsEmpty,
        (ExportLayer.buildings, ExportLayerIssue.missingRequiredFields) =>
          l.exportValidationBuildingsMissingFields,
        (ExportLayer.roads, ExportLayerIssue.missingRequiredFields) =>
          l.exportValidationRoadsMissingFields,
      };

  Future<void> _onUploadDataTap(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
  ) async {
    final biometric = ref.read(biometricGateProvider);
    final available = await biometric.isAvailable();
    if (!available) {
      if (context.mounted) context.go('/review');
      return;
    }
    final ok = await biometric.authenticate(reason: l.biometricGateReason);
    if (!ok) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.biometricFailedSnackbar)),
        );
      }
      return;
    }
    if (context.mounted) context.go('/review');
  }
}

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
        enabled: onTap != null,
      ),
    );
  }
}
```

- [ ] **Step 5: Run analyze**

Run: `cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter analyze`

Expected: `No issues found!`

- [ ] **Step 6: Run full test suite**

Run: `cd "/Users/johnlesterescarlan/Personal Projects/firecheck" && flutter test`

Expected: All tests pass (count will be existing tests + 7 new ones added across tasks 2, 4, 5).

- [ ] **Step 7: Commit**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck"
git add lib/core/i18n/app_en.arb \
        lib/core/i18n/app_tl.arb \
        lib/features/home/presentation/home_screen.dart
git commit -m "feat(export-validation): add l10n keys and inline validation errors on HomeScreen"
```
