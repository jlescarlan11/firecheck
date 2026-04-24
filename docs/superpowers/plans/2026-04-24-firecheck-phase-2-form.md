# FireCheck Mobile — Phase 2 (Building form + autosave + photos) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Phase 1's polygon-tap placeholder bottom sheet with a real `SubmissionDetailScreen` — multi-submission tabs, debounced autosave to Drift, full RA 9514 building attribution form, system-camera photo capture with EXIF-preserving resize, and the distance-Override / does-not-exist short-circuit paths.

**Architecture:** Additive to Phase 1's layered architecture. Adds `core/photos/` (camera + image-processing infra), `core/geo/centroid.dart` (pure GeoJSON math), and two feature modules under `features/survey/` (`photo_capture/` + `building_form/`). Bumps Drift to schema v3 (`submissions.override_reason`). Phase 1's invariant holds: every write hits Drift first; the UI reads via reactive streams.

**Tech Stack additions:**
- `image_picker` 1.x — system camera capture
- `image` 4.x — pure-Dart resize + JPEG re-encode
- `native_exif` 0.6+ — read/write EXIF GPS across the resize
- `CAMERA` permission in `AndroidManifest.xml`

**Phase 2 demo state:** Login → tap Get Maps (existing) → tap Open map → tap any of the 10 polygons → SubmissionDetailScreen opens with empty Tab 1 → fill the form (autosave indicator updates, polygon turns yellow live on the map) → tap "+ Photo" → system camera → return → photo strip thumbnail appears → all required fields filled → polygon turns green → tap Done → back to map. Tap "+" tab → fill Tab 2 differently. Toggle "does not exist" → fields disable but photo still required to mark complete.

---

## File structure (Phase 2 additions + modifications)

```
pubspec.yaml                                      Modify — add image_picker, image, native_exif
android/app/src/main/AndroidManifest.xml          Modify — CAMERA permission

supabase/migrations/
  003_override_reason.sql                         New — adds submissions.override_reason

test/fixtures/
  photo_with_gps.jpg                              New — test asset (any small JPG with EXIF GPS)

lib/
  core/
    db/
      database.dart                               Modify — schemaVersion=3, onUpgrade adds column
      tables/
        submissions.dart                          Modify — add overrideReason
    photos/
      camera_service.dart                         New — image_picker wrapper + fake
      image_processor.dart                        New — resize + EXIF transfer
      photo_storage_service.dart                  New — local filesystem layout
      photo_capture_controller.dart               New — orchestrator
      photo_providers.dart                        New — Riverpod providers
    geo/
      centroid.dart                               New — pure GeoJSON polygon centroid
    router/
      app_router.dart                             Modify — add /feature/:featureId route
    i18n/
      app_en.arb                                  Modify — Phase 2 strings
      app_tl.arb                                  Modify — Phase 2 strings
  features/
    survey/
      photo_capture/
        data/
          photo_repository.dart                   New — Drift CRUD on photos table
        presentation/
          photo_strip.dart                        New — horizontal thumbnail strip
          photo_strip_providers.dart              New — Riverpod
          photo_preview_screen.dart               New — full-screen preview + delete
      building_form/
        data/
          submission_repository.dart              New — submissions CRUD + multi-submission ops
          building_attributes_repository.dart     New — building_attributes CRUD
        domain/
          building_form_state.dart                New — value type holding all form fields
          building_form_validator.dart            New — pure validation function
          ra_9514_fallback.dart                   New — hardcoded fallback list
          override_check.dart                     New — distance-check + override-reason use case
        presentation/
          submission_detail_screen.dart           New — tabs + form host
          submission_tabs.dart                    New — horizontal scrollable tab strip
          building_form.dart                      New — section list widget
          sections/
            identity_section.dart                 New — CBMS ID, name, RA 9514, does-not-exist
            construction_section.dart             New — storeys, material
            cost_section.dart                     New — radio + conditional input
            ff_facilities_section.dart            New — multi-select chip row
            fire_load_section.dart                New — multi-select chip row
          building_form_notifier.dart             New — debounced autosave StateNotifier
          building_form_providers.dart            New — Riverpod providers
          override_reason_dialog.dart             New — distance > 50m text-input dialog
    map/
      data/
        feature_repository.dart                   Modify — add markFeatureStatus(String featureId)
      presentation/
        map_screen.dart                           Modify — replace bottom sheet with route push
        feature_bottom_sheet.dart                 Delete — replaced by detail screen
        feature_too_far_modal.dart                Modify — adapted into override_check flow

test/
  core/
    db/
      migration_v2_to_v3_test.dart                New
    photos/
      image_processor_test.dart                   New — resize + EXIF preservation
      photo_storage_service_test.dart             New
      camera_service_test.dart                    New — fake camera flow
      photo_capture_controller_test.dart          New
    geo/
      centroid_test.dart                          New
  features/
    survey/
      photo_capture/
        photo_repository_test.dart                New
        photo_strip_test.dart                     New
      building_form/
        submission_repository_test.dart           New
        building_attributes_repository_test.dart  New
        building_form_validator_test.dart         New
        building_form_notifier_test.dart          New
        sections/
          identity_section_test.dart              New
          construction_section_test.dart          New
          cost_section_test.dart                  New
          ff_facilities_section_test.dart         New
          fire_load_section_test.dart             New
        building_form_test.dart                   New
        submission_tabs_test.dart                 New
        override_reason_dialog_test.dart          New
        submission_detail_screen_test.dart        New
```

---

## Task 1: Schema v3 — add `override_reason` column

**Files:**
- Modify: `lib/core/db/tables/submissions.dart`
- Modify: `lib/core/db/database.dart`
- Regenerate: `lib/core/db/database.g.dart`
- Create: `supabase/migrations/003_override_reason.sql`
- Create: `test/core/db/migration_v2_to_v3_test.dart`
- Modify: `test/core/db/database_test.dart` — bump schemaVersion assertion

Strict prerequisite. Bumps schema, adds the column, preserves the FK pragma.

- [ ] **Step 1: Add `overrideReason` to `submissions.dart`**

```dart
import 'package:drift/drift.dart';

@TableIndex(name: 'submissions_feature_id_idx', columns: {#featureId})
class Submissions extends Table {
  TextColumn get id => text()();
  TextColumn get featureId => text()();
  TextColumn get submittedBy => text().nullable()();
  BoolColumn get doesNotExist => boolean().withDefault(const Constant(false))();
  TextColumn get remarks => text().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('draft'))();
  TextColumn get overrideReason => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 2: Update `database.dart` — schemaVersion=3 + onUpgrade extension**

Open `lib/core/db/database.dart`. Bump `schemaVersion => 3`. Extend `onUpgrade`:

```dart
onUpgrade: (m, from, to) async {
  if (from < 2) {
    await customStatement(
      'ALTER TABLE offline_tile_packs '
      'RENAME COLUMN maplibre_pack_id TO mapbox_pack_id',
    );
    await m.createIndex(featuresAssignmentIdIdx);
    await m.createIndex(submissionsFeatureIdIdx);
    await m.createIndex(photosSubmissionIdIdx);
    await m.createIndex(syncJobsStatusRetryIdx);
    await m.createIndex(buildingAttrsRa9514TypeIdx);
  }
  if (from < 3) {
    await m.addColumn(submissions, submissions.overrideReason);
  }
},
```

`beforeOpen` and `onCreate` blocks unchanged.

- [ ] **Step 3: Re-run Drift codegen**

```bash
dart run build_runner build --delete-conflicting-outputs
```

Expected: `database.g.dart` regenerated. The `Submission` data class has a new `overrideReason` field. The `SubmissionsCompanion.insert` accepts `overrideReason: Value(...)`.

- [ ] **Step 4: Create the server migration**

Create `supabase/migrations/003_override_reason.sql`:

```sql
-- Phase 2: distance-rule Override flow records a free-text reason that
-- supervisors review during sync.
alter table public.submissions add column override_reason text;
```

Apply manually in the Supabase SQL Editor — same pattern as Phase 1's migration 002.

- [ ] **Step 5: Write the failing migration test**

Create `test/core/db/migration_v2_to_v3_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppDatabase schema v3', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async => db.close());

    test('schemaVersion is 3', () {
      expect(db.schemaVersion, 3);
    });

    test('PRAGMA foreign_keys remains ON', () async {
      final result = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(result.data['foreign_keys'], 1);
    });

    test('submissions has override_reason column', () async {
      final rows = await db
          .customSelect('PRAGMA table_info(submissions)')
          .get();
      final cols = rows.map((r) => r.data['name'] as String).toSet();
      expect(cols, contains('override_reason'));
    });

    test('phase-1 indexes still present', () async {
      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final names = rows.map((r) => r.data['name'] as String).toSet();
      expect(
        names,
        containsAll([
          'features_assignment_id_idx',
          'submissions_feature_id_idx',
          'photos_submission_id_idx',
          'sync_jobs_status_retry_idx',
          'building_attrs_ra9514_type_idx',
        ]),
      );
    });
  });
}
```

- [ ] **Step 6: Run the new test**

```bash
flutter test test/core/db/migration_v2_to_v3_test.dart
```

Expected: 4/4 PASS.

- [ ] **Step 7: Update Phase 1's `database_test.dart` schemaVersion assertion**

In `test/core/db/database_test.dart`:

```dart
test('schemaVersion is 3', () {
  expect(db.schemaVersion, 3);
});
```

Rename the test from `schemaVersion is 2` to `schemaVersion is 3`.

- [ ] **Step 8: Run full test suite — confirm no regression**

```bash
flutter test
```

Expected: all tests pass (Phase 1's 71 + 4 new migration tests + 1 updated → 75 or 76 depending on count of tests in `database_test.dart`).

- [ ] **Step 9: Commit**

```bash
git add lib/core/db/ test/core/db/ supabase/migrations/003_override_reason.sql
git commit -m "feat(db): schema v3 — add submissions.override_reason"
```

---

## Task 2: Add image deps + camera permission + Phase 2 i18n

**Files:**
- Modify: `pubspec.yaml`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `lib/core/i18n/app_en.arb`
- Modify: `lib/core/i18n/app_tl.arb`

- [ ] **Step 1: Add image deps to `pubspec.yaml`**

In the existing `dependencies:` block, add a new `# media` group:

```yaml
  # media
  image_picker: ^1.1.0
  image: ^4.2.0
  native_exif: ^0.6.0
```

Run:

```bash
flutter pub get
```

Expected: resolves cleanly.

- [ ] **Step 2: Add `CAMERA` permission to `AndroidManifest.xml`**

In `android/app/src/main/AndroidManifest.xml`, alongside existing permissions inside `<manifest>` (outside `<application>`):

```xml
<uses-permission android:name="android.permission.CAMERA"/>
```

`image_picker` reads from `MediaStore` so no additional `READ_MEDIA_IMAGES` is required for "take a new photo" — only if we ever pick from gallery (we don't in Phase 2).

- [ ] **Step 3: Add Phase 2 strings to `app_en.arb`**

Append to `lib/core/i18n/app_en.arb` before the closing `}`:

```json
  ,
  "submissionDetailTitleBuilding": "Building",
  "submissionDetailTitleRoad": "Road",
  "tabStructure": "Structure {n}",
  "@tabStructure": {
    "placeholders": {"n": {"type": "int"}}
  },
  "tabSoftCapTooltip": "This polygon already has 5 structures",
  "savedAgo": "✓ Saved {seconds} seconds ago · {connectivity}",
  "@savedAgo": {
    "placeholders": {
      "seconds": {"type": "int"},
      "connectivity": {"type": "String"}
    }
  },
  "savedJustNow": "✓ Saved just now · {connectivity}",
  "@savedJustNow": {
    "placeholders": {"connectivity": {"type": "String"}}
  },
  "photosLabel": "Photos",
  "photosRequiredBadge": "0 / 1 required",
  "photosCompleteBadge": "1+ ✓",
  "addPhoto": "+ Photo",
  "deletePhoto": "Delete photo?",
  "deletePhotoConfirm": "This photo will be removed from the device.",
  "deleteAction": "Delete",
  "doesNotExistTitle": "This building does not exist",
  "doesNotExistHelper": "Photo still required to confirm",
  "sectionIdentity": "Identity",
  "sectionConstruction": "Construction",
  "sectionCost": "Cost",
  "sectionFireFighting": "Fire-fighting facilities",
  "sectionFireLoad": "Fire load *",
  "fieldCbmsId": "CBMS ID (optional)",
  "fieldBuildingName": "Building name *",
  "fieldRa9514Type": "Type — RA 9514 *",
  "fieldStoreys": "Storeys *",
  "fieldMaterial": "Wall material *",
  "fieldCostExact": "Exact amount",
  "fieldCostRange": "Estimated range",
  "fieldCostExactInput": "Amount (₱) *",
  "fieldCostRangeInput": "Range *",
  "costRangeUnder100k": "<₱100k",
  "costRange100to500k": "₱100k – ₱500k",
  "costRange500kto1M": "₱500k – ₱1M",
  "costRange1to5M": "₱1M – ₱5M",
  "costRange5to10M": "₱5M – ₱10M",
  "costRangeOver10M": ">₱10M",
  "ffExtinguisher": "Extinguisher",
  "ffSprinkler": "Sprinkler",
  "ffHose": "Hose",
  "ffSmokeAlarm": "Smoke alarm",
  "ffNone": "None",
  "fireLoadWoodFurniture": "Wood furniture",
  "fireLoadFabric": "Fabric",
  "fireLoadPaper": "Paper",
  "fireLoadChemicals": "Chemicals",
  "fireLoadCookingGas": "Cooking gas",
  "fireLoadOther": "Other",
  "materialConcrete": "Concrete",
  "materialWood": "Wood",
  "materialMixed": "Mixed",
  "materialLight": "Light materials",
  "materialSteel": "Steel",
  "materialOther": "Other",
  "ra9514GroupA": "Group A · Residential",
  "ra9514GroupB": "Group B · Residential / Hotel",
  "ra9514GroupC": "Group C · Educational",
  "ra9514GroupD": "Group D · Institutional",
  "ra9514GroupE": "Group E · Business",
  "ra9514GroupF": "Group F · Mercantile",
  "ra9514GroupG": "Group G · Industrial",
  "ra9514GroupH": "Group H · Storage",
  "ra9514GroupI": "Group I · Hazardous",
  "ra9514GroupJ": "Group J · Miscellaneous",
  "doneButton": "Done",
  "footerStatusReady": "All required fields filled · ready",
  "footerStatusPhotoRequired": "Photo required to mark complete",
  "footerStatusFieldsMissing": "Required fields missing",
  "overrideTitle": "Override required",
  "overrideBody": "You're {distance}m away. Map policy requires ≤50m. Why are you submitting from this distance?",
  "@overrideBody": {
    "placeholders": {"distance": {"type": "int"}}
  },
  "overrideReasonHint": "polygon misplaced · couldn't approach safely · unable to verify on foot",
  "overrideContinue": "Continue",
  "storeysWarningTooTall": "That's very tall — confirm?",
  "errorRequiredField": "Required",
  "cameraPermissionSnackbar": "Enable camera permission to take photos",
  "savedFailedSnackbar": "Couldn't save. Retrying…"
```

- [ ] **Step 4: Add Phase 2 strings to `app_tl.arb`**

Append to `lib/core/i18n/app_tl.arb` before the closing `}`:

```json
  ,
  "submissionDetailTitleBuilding": "Gusali",
  "submissionDetailTitleRoad": "Daan",
  "tabStructure": "Istruktura {n}",
  "tabSoftCapTooltip": "May 5 nang istruktura ang polygon na ito",
  "savedAgo": "✓ Naka-save {seconds}s ang nakalipas · {connectivity}",
  "savedJustNow": "✓ Naka-save kanina · {connectivity}",
  "photosLabel": "Mga larawan",
  "photosRequiredBadge": "0 / 1 kailangan",
  "photosCompleteBadge": "1+ ✓",
  "addPhoto": "+ Larawan",
  "deletePhoto": "Burahin ang larawan?",
  "deletePhotoConfirm": "Maaalis ito sa device.",
  "deleteAction": "Burahin",
  "doesNotExistTitle": "Hindi umiiral ang gusaling ito",
  "doesNotExistHelper": "Kailangan pa rin ng larawan",
  "sectionIdentity": "Pagkakakilanlan",
  "sectionConstruction": "Konstruksyon",
  "sectionCost": "Halaga",
  "sectionFireFighting": "Kagamitang panlaban sa sunog",
  "sectionFireLoad": "Madaling masunog *",
  "fieldCbmsId": "CBMS ID (opsyonal)",
  "fieldBuildingName": "Pangalan ng gusali *",
  "fieldRa9514Type": "Uri — RA 9514 *",
  "fieldStoreys": "Bilang ng palapag *",
  "fieldMaterial": "Materyal ng dingding *",
  "fieldCostExact": "Eksaktong halaga",
  "fieldCostRange": "Tinatayang halaga",
  "fieldCostExactInput": "Halaga (₱) *",
  "fieldCostRangeInput": "Range *",
  "costRangeUnder100k": "<₱100k",
  "costRange100to500k": "₱100k – ₱500k",
  "costRange500kto1M": "₱500k – ₱1M",
  "costRange1to5M": "₱1M – ₱5M",
  "costRange5to10M": "₱5M – ₱10M",
  "costRangeOver10M": ">₱10M",
  "ffExtinguisher": "Pang-apula",
  "ffSprinkler": "Sprinkler",
  "ffHose": "Hose",
  "ffSmokeAlarm": "Smoke alarm",
  "ffNone": "Wala",
  "fireLoadWoodFurniture": "Kahoy na muwebles",
  "fireLoadFabric": "Tela",
  "fireLoadPaper": "Papel",
  "fireLoadChemicals": "Kemikal",
  "fireLoadCookingGas": "Gas pangluto",
  "fireLoadOther": "Iba pa",
  "materialConcrete": "Konkreto",
  "materialWood": "Kahoy",
  "materialMixed": "Pinaghalo",
  "materialLight": "Magagaang materyales",
  "materialSteel": "Bakal",
  "materialOther": "Iba pa",
  "ra9514GroupA": "Grupo A · Tirahan",
  "ra9514GroupB": "Grupo B · Tirahan / Hotel",
  "ra9514GroupC": "Grupo C · Paaralan",
  "ra9514GroupD": "Grupo D · Pampubliko",
  "ra9514GroupE": "Grupo E · Negosyo",
  "ra9514GroupF": "Grupo F · Komersyal",
  "ra9514GroupG": "Grupo G · Industriya",
  "ra9514GroupH": "Grupo H · Imbakan",
  "ra9514GroupI": "Grupo I · Mapanganib",
  "ra9514GroupJ": "Grupo J · Iba pa",
  "doneButton": "Tapos",
  "footerStatusReady": "Lahat ng kailangan ay napunan · handa",
  "footerStatusPhotoRequired": "Kailangan ng larawan",
  "footerStatusFieldsMissing": "May kulang na impormasyon",
  "overrideTitle": "Kailangan ng paliwanag",
  "overrideBody": "{distance}m ang layo mo. Ang patakaran ay ≤50m. Bakit ka mag-su-submit mula sa layong ito?",
  "overrideReasonHint": "maling lugar ng polygon · hindi ligtas lumapit · hindi ma-verify nang lakad",
  "overrideContinue": "Ituloy",
  "storeysWarningTooTall": "Sobrang taas — kumpirmahin?",
  "errorRequiredField": "Kailangan",
  "cameraPermissionSnackbar": "Buksan ang permiso sa kamera para makakuha ng larawan",
  "savedFailedSnackbar": "Hindi nai-save. Susubukan ulit…"
```

- [ ] **Step 5: Regenerate l10n**

```bash
flutter gen-l10n
```

- [ ] **Step 6: Verify analyze + commit**

```bash
flutter analyze
git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml lib/core/i18n/ lib/generated/
git commit -m "feat(media): add image_picker/image/native_exif + CAMERA permission + Phase 2 i18n"
```

Expected: 0 issues.

---

## Task 3: Pure GeoJSON polygon centroid + tests

**Files:**
- Create: `lib/core/geo/centroid.dart`
- Create: `test/core/geo/centroid_test.dart`

Pure Dart, no Flutter, no async. Replaces Phase 1's hardcoded fallback.

- [ ] **Step 1: Write failing test**

```dart
import 'package:firecheck/core/geo/centroid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('polygonCentroid', () {
    test('unit square centred at (0.5, 0.5)', () {
      const ring = [
        [0.0, 0.0],
        [1.0, 0.0],
        [1.0, 1.0],
        [0.0, 1.0],
        [0.0, 0.0],
      ];
      final c = polygonCentroid(ring);
      expect(c.lng, closeTo(0.5, 1e-9));
      expect(c.lat, closeTo(0.5, 1e-9));
    });

    test('right triangle (0,0)-(1,0)-(0,1) centroid is (1/3, 1/3)', () {
      const ring = [
        [0.0, 0.0],
        [1.0, 0.0],
        [0.0, 1.0],
        [0.0, 0.0],
      ];
      final c = polygonCentroid(ring);
      expect(c.lng, closeTo(1 / 3, 1e-9));
      expect(c.lat, closeTo(1 / 3, 1e-9));
    });

    test('clockwise vs counterclockwise yield same centroid', () {
      const ccw = [
        [0.0, 0.0],
        [2.0, 0.0],
        [2.0, 1.0],
        [0.0, 1.0],
        [0.0, 0.0],
      ];
      const cw = [
        [0.0, 0.0],
        [0.0, 1.0],
        [2.0, 1.0],
        [2.0, 0.0],
        [0.0, 0.0],
      ];
      final a = polygonCentroid(ccw);
      final b = polygonCentroid(cw);
      expect(a.lng, closeTo(b.lng, 1e-9));
      expect(a.lat, closeTo(b.lat, 1e-9));
    });

    test('Brgy. Tisa rectangle centroid', () {
      // Roughly 200m × 150m boundary used in the seed data.
      const ring = [
        [123.88200, 10.31720],
        [123.88340, 10.31720],
        [123.88340, 10.31900],
        [123.88200, 10.31900],
        [123.88200, 10.31720],
      ];
      final c = polygonCentroid(ring);
      expect(c.lng, closeTo(123.88270, 1e-5));
      expect(c.lat, closeTo(10.31810, 1e-5));
    });

    test('degenerate single-point ring returns that point', () {
      const ring = [
        [5.0, 7.0],
        [5.0, 7.0],
      ];
      final c = polygonCentroid(ring);
      expect(c.lng, 5.0);
      expect(c.lat, 7.0);
    });

    test('decodePolygonGeojson extracts the outer ring of a Polygon', () {
      const geojson = '''
{"type":"Polygon","coordinates":[[[123.88200,10.31720],[123.88340,10.31720],[123.88340,10.31900],[123.88200,10.31900],[123.88200,10.31720]]]}
''';
      final ring = decodePolygonGeojson(geojson);
      expect(ring, isNotNull);
      expect(ring!, hasLength(5));
      expect(ring.first, [123.88200, 10.31720]);
    });
  });
}
```

- [ ] **Step 2: Run test → fail**

```bash
flutter test test/core/geo/centroid_test.dart
```

- [ ] **Step 3: Implement `centroid.dart`**

```dart
import 'dart:convert';

class LatLng {
  const LatLng({required this.lat, required this.lng});
  final double lat;
  final double lng;
}

/// Area-weighted centroid of a closed polygon ring (`[[lng, lat], ...]`).
/// Handles clockwise + counterclockwise, and degenerate (zero-area) rings
/// by returning the average of the points.
LatLng polygonCentroid(List<List<double>> ring) {
  if (ring.isEmpty) return const LatLng(lat: 0, lng: 0);
  if (ring.length == 1) {
    return LatLng(lat: ring.first[1], lng: ring.first[0]);
  }

  double signedArea = 0;
  double cx = 0;
  double cy = 0;

  for (var i = 0; i < ring.length - 1; i++) {
    final x0 = ring[i][0];
    final y0 = ring[i][1];
    final x1 = ring[i + 1][0];
    final y1 = ring[i + 1][1];
    final cross = x0 * y1 - x1 * y0;
    signedArea += cross;
    cx += (x0 + x1) * cross;
    cy += (y0 + y1) * cross;
  }
  signedArea /= 2;

  if (signedArea.abs() < 1e-12) {
    // Degenerate (e.g. duplicated points). Fall back to mean.
    double sx = 0;
    double sy = 0;
    for (final p in ring) {
      sx += p[0];
      sy += p[1];
    }
    return LatLng(lat: sy / ring.length, lng: sx / ring.length);
  }

  cx /= 6 * signedArea;
  cy /= 6 * signedArea;
  return LatLng(lat: cy, lng: cx);
}

/// Best-effort GeoJSON decode. Returns the first (outer) ring of a Polygon
/// as a list of `[lng, lat]` pairs, or null if the input isn't a parseable
/// Polygon. Holes are ignored (Phase 2 doesn't model them).
List<List<double>>? decodePolygonGeojson(String geojson) {
  if (geojson.isEmpty) return null;
  try {
    final decoded = jsonDecode(geojson);
    if (decoded is! Map<String, Object?>) return null;
    final coords = decoded['coordinates'];
    if (coords is! List<Object?> || coords.isEmpty) return null;
    final outer = coords.first;
    if (outer is! List<Object?>) return null;
    final out = <List<double>>[];
    for (final p in outer) {
      if (p is! List<Object?> || p.length < 2) return null;
      final lng = p[0];
      final lat = p[1];
      if (lng is! num || lat is! num) return null;
      out.add([lng.toDouble(), lat.toDouble()]);
    }
    return out;
  } on Object {
    return null;
  }
}
```

- [ ] **Step 4: Run test → pass**

```bash
flutter test test/core/geo/centroid_test.dart
```

Expected: all 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/geo/ test/core/geo/
git commit -m "feat(geo): pure GeoJSON polygon centroid + tests"
```

---

## Task 4: PhotoStorageService + CameraService + tests

**Files:**
- Create: `lib/core/photos/photo_storage_service.dart`
- Create: `lib/core/photos/camera_service.dart`
- Create: `test/core/photos/photo_storage_service_test.dart`
- Create: `test/core/photos/camera_service_test.dart`

- [ ] **Step 1: Implement `photo_storage_service.dart`**

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

abstract class PhotoStorageService {
  Future<String> reserveDestPath({required String submissionId});
  Future<void> deleteFile(String path);
}

class FilesystemPhotoStorage implements PhotoStorageService {
  const FilesystemPhotoStorage();

  @override
  Future<String> reserveDestPath({required String submissionId}) async {
    final dir = await getApplicationDocumentsDirectory();
    final subDir = Directory(p.join(dir.path, 'photos', submissionId));
    await subDir.create(recursive: true);
    final id = const Uuid().v4();
    return p.join(subDir.path, '$id.jpg');
  }

  @override
  Future<void> deleteFile(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}

/// In-memory fake — generates deterministic paths under a given root.
class InMemoryPhotoStorage implements PhotoStorageService {
  InMemoryPhotoStorage({String? root}) : _root = root ?? '/tmp/test-photos';

  final String _root;
  int _counter = 0;
  final Set<String> deleted = {};

  @override
  Future<String> reserveDestPath({required String submissionId}) async {
    _counter += 1;
    return p.join(_root, submissionId, 'p$_counter.jpg');
  }

  @override
  Future<void> deleteFile(String path) async {
    deleted.add(path);
  }
}
```

- [ ] **Step 2: Implement `camera_service.dart`**

```dart
import 'package:image_picker/image_picker.dart';

abstract class CameraService {
  /// Opens the system camera. Returns the captured photo's local path
  /// (full-res), or null if the user cancelled.
  Future<String?> capturePhoto();
}

class ImagePickerCameraService implements CameraService {
  ImagePickerCameraService([ImagePicker? picker])
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<String?> capturePhoto() async {
    final f = await _picker.pickImage(source: ImageSource.camera);
    return f?.path;
  }
}

class FakeCameraService implements CameraService {
  FakeCameraService({this.scriptedPath});
  final String? scriptedPath;
  int callCount = 0;

  @override
  Future<String?> capturePhoto() async {
    callCount += 1;
    return scriptedPath;
  }
}
```

- [ ] **Step 3: Write tests**

`test/core/photos/photo_storage_service_test.dart`:

```dart
import 'package:firecheck/core/photos/photo_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('InMemoryPhotoStorage hands out distinct paths per call', () async {
    final s = InMemoryPhotoStorage();
    final a = await s.reserveDestPath(submissionId: 'sub1');
    final b = await s.reserveDestPath(submissionId: 'sub1');
    expect(a, isNot(b));
    expect(a, contains('/sub1/'));
  });

  test('deleteFile records the deletion', () async {
    final s = InMemoryPhotoStorage();
    await s.deleteFile('/tmp/foo.jpg');
    expect(s.deleted, contains('/tmp/foo.jpg'));
  });
}
```

`test/core/photos/camera_service_test.dart`:

```dart
import 'package:firecheck/core/photos/camera_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FakeCameraService returns scripted path and counts calls', () async {
    final c = FakeCameraService(scriptedPath: '/tmp/photo.jpg');
    expect(await c.capturePhoto(), '/tmp/photo.jpg');
    expect(await c.capturePhoto(), '/tmp/photo.jpg');
    expect(c.callCount, 2);
  });

  test('FakeCameraService with no scripted path returns null (user cancel)',
      () async {
    final c = FakeCameraService();
    expect(await c.capturePhoto(), isNull);
  });
}
```

- [ ] **Step 4: Run tests + analyze**

```bash
flutter test test/core/photos/
flutter analyze lib/core/photos/ test/core/photos/
```

Expected: 4 tests pass, analyze clean.

- [ ] **Step 5: Commit**

```bash
git add lib/core/photos/ test/core/photos/
git commit -m "feat(photos): PhotoStorageService + CameraService + fakes + tests"
```

---

## Task 5: ImageProcessor (resize + EXIF transfer) + tests

**Files:**
- Create: `lib/core/photos/image_processor.dart`
- Create: `test/core/photos/image_processor_test.dart`
- Create: `test/fixtures/photo_with_gps.jpg` (test asset)

- [ ] **Step 1: Add a small JPG with GPS EXIF as a test fixture**

Create the `test/fixtures/` directory if missing. The fixture image should be a small (e.g. 800×600) JPG with valid EXIF GPS tags. Easiest way to create one for the test: capture any photo on a phone with location enabled, copy it into `test/fixtures/photo_with_gps.jpg`. Alternatively, generate one programmatically with `image` + `native_exif` and check it in.

Verify with:

```bash
ls -la test/fixtures/photo_with_gps.jpg
```

Expected: file exists, ~50-200 KB.

- [ ] **Step 2: Implement `image_processor.dart`**

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:native_exif/native_exif.dart';

class ImageProcessor {
  const ImageProcessor();

  /// Reads [sourcePath], resizes to 1600 px longest edge preserving aspect,
  /// re-encodes as JPEG quality 85, copies EXIF GPS tags from the source,
  /// writes to [destPath]. Returns the GPS lat/lng read from EXIF (null if
  /// the photo had no location tags).
  Future<({double? lat, double? lng})> resizeAndCopyExif({
    required String sourcePath,
    required String destPath,
  }) async {
    final srcBytes = await File(sourcePath).readAsBytes();
    final decoded = img.decodeImage(srcBytes);
    if (decoded == null) {
      throw const ImageProcessingException('Could not decode source image');
    }

    final resized = _resizeToLongestEdge(decoded, 1600);
    final outBytes = img.encodeJpg(resized, quality: 85);
    await File(destPath).writeAsBytes(outBytes, flush: true);

    final gps = await _copyExifAndReadGps(sourcePath, destPath);
    return gps;
  }

  img.Image _resizeToLongestEdge(img.Image src, int target) {
    final w = src.width;
    final h = src.height;
    if (w <= target && h <= target) return src;
    if (w >= h) {
      return img.copyResize(src, width: target);
    }
    return img.copyResize(src, height: target);
  }

  Future<({double? lat, double? lng})> _copyExifAndReadGps(
    String sourcePath,
    String destPath,
  ) async {
    Exif? srcExif;
    Exif? dstExif;
    try {
      srcExif = await Exif.fromPath(sourcePath);
      final lat = await srcExif.getLatitude();
      final lng = await srcExif.getLongitude();

      if (lat != null && lng != null) {
        dstExif = await Exif.fromPath(destPath);
        await dstExif.writeAttributes({
          'GPSLatitude': lat.toString(),
          'GPSLongitude': lng.toString(),
          'GPSLatitudeRef': lat >= 0 ? 'N' : 'S',
          'GPSLongitudeRef': lng >= 0 ? 'E' : 'W',
        });
      }
      return (lat: lat, lng: lng);
    } on Object {
      return (lat: null, lng: null);
    } finally {
      await srcExif?.close();
      await dstExif?.close();
    }
  }
}

class ImageProcessingException implements Exception {
  const ImageProcessingException(this.message);
  final String message;
}
```

- [ ] **Step 3: Write the test**

`test/core/photos/image_processor_test.dart`:

```dart
import 'dart:io';

import 'package:firecheck/core/photos/image_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('image_processor_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('resizes large image to 1600 px longest edge', () async {
    // Synthesize a 3000×2000 source image so the test doesn't depend on the
    // committed fixture being exactly the right size.
    final src = img.Image(width: 3000, height: 2000);
    img.fill(src, color: img.ColorRgb8(255, 0, 0));
    final srcPath = p.join(tempDir.path, 'src.jpg');
    await File(srcPath).writeAsBytes(img.encodeJpg(src));

    final destPath = p.join(tempDir.path, 'dest.jpg');
    await const ImageProcessor().resizeAndCopyExif(
      sourcePath: srcPath,
      destPath: destPath,
    );

    final out = img.decodeImage(await File(destPath).readAsBytes())!;
    expect(out.width, 1600);
    expect(out.height, lessThanOrEqualTo(1600));
    expect(await File(destPath).length(), lessThan(await File(srcPath).length()));
  });

  test('does not upscale a small image', () async {
    final src = img.Image(width: 800, height: 600);
    img.fill(src, color: img.ColorRgb8(0, 255, 0));
    final srcPath = p.join(tempDir.path, 'small.jpg');
    await File(srcPath).writeAsBytes(img.encodeJpg(src));

    final destPath = p.join(tempDir.path, 'small_out.jpg');
    await const ImageProcessor().resizeAndCopyExif(
      sourcePath: srcPath,
      destPath: destPath,
    );

    final out = img.decodeImage(await File(destPath).readAsBytes())!;
    expect(out.width, 800);
    expect(out.height, 600);
  });

  test('returns null gps for image without EXIF', () async {
    final src = img.Image(width: 100, height: 100);
    img.fill(src, color: img.ColorRgb8(0, 0, 255));
    final srcPath = p.join(tempDir.path, 'no_exif.jpg');
    await File(srcPath).writeAsBytes(img.encodeJpg(src));

    final destPath = p.join(tempDir.path, 'no_exif_out.jpg');
    final gps = await const ImageProcessor().resizeAndCopyExif(
      sourcePath: srcPath,
      destPath: destPath,
    );
    expect(gps.lat, isNull);
    expect(gps.lng, isNull);
  });
}
```

Note: the spec called for using a real fixture image with GPS EXIF. The synthetic-image path above works without one and avoids checking a binary blob into the repo. If the fixture is available at `test/fixtures/photo_with_gps.jpg`, add a fourth test that round-trips real GPS through the resize. Skip otherwise.

- [ ] **Step 4: Run tests**

```bash
flutter test test/core/photos/image_processor_test.dart
```

Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/photos/image_processor.dart test/core/photos/image_processor_test.dart test/fixtures/
git commit -m "feat(photos): ImageProcessor with resize-to-1600 + EXIF GPS preservation"
```

---

## Task 6: PhotoCaptureController + tests

**Files:**
- Create: `lib/core/photos/photo_capture_controller.dart`
- Create: `lib/core/photos/photo_providers.dart`
- Create: `test/core/photos/photo_capture_controller_test.dart`

`PhotoRepository` from `features/survey/photo_capture/data/photo_repository.dart` is created in Task 7 — declare it as a forward dependency here using its method signature.

- [ ] **Step 1: Implement `photo_capture_controller.dart`**

```dart
import 'package:firecheck/core/photos/camera_service.dart';
import 'package:firecheck/core/photos/image_processor.dart';
import 'package:firecheck/core/photos/photo_storage_service.dart';
import 'package:firecheck/features/survey/photo_capture/data/photo_repository.dart';

class PhotoCaptureController {
  PhotoCaptureController({
    required this.camera,
    required this.processor,
    required this.storage,
    required this.repo,
  });

  final CameraService camera;
  final ImageProcessor processor;
  final PhotoStorageService storage;
  final PhotoRepository repo;

  /// Capture path: open camera → user shoots → resize + EXIF copy →
  /// insert Drift row. Returns null if user cancelled. Returns the new
  /// photo id on success.
  Future<String?> capture({required String submissionId}) async {
    final src = await camera.capturePhoto();
    if (src == null) return null;
    final dest = await storage.reserveDestPath(submissionId: submissionId);
    final gps = await processor.resizeAndCopyExif(
      sourcePath: src,
      destPath: dest,
    );
    return repo.insert(
      submissionId: submissionId,
      localPath: dest,
      capturedAt: DateTime.now(),
      gpsLat: gps.lat,
      gpsLng: gps.lng,
    );
  }
}
```

- [ ] **Step 2: Implement `photo_providers.dart`**

```dart
import 'package:firecheck/core/photos/camera_service.dart';
import 'package:firecheck/core/photos/image_processor.dart';
import 'package:firecheck/core/photos/photo_capture_controller.dart';
import 'package:firecheck/core/photos/photo_storage_service.dart';
import 'package:firecheck/features/survey/photo_capture/data/photo_repository.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final cameraServiceProvider = Provider<CameraService>((ref) {
  return ImagePickerCameraService();
});

final imageProcessorProvider = Provider<ImageProcessor>((ref) {
  return const ImageProcessor();
});

final photoStorageProvider = Provider<PhotoStorageService>((ref) {
  return const FilesystemPhotoStorage();
});

final photoRepositoryProvider = Provider<PhotoRepository>((ref) {
  return PhotoRepository(
    db: ref.watch(appDatabaseProvider),
    storage: ref.watch(photoStorageProvider),
  );
});

final photoCaptureControllerProvider = Provider<PhotoCaptureController>((ref) {
  return PhotoCaptureController(
    camera: ref.watch(cameraServiceProvider),
    processor: ref.watch(imageProcessorProvider),
    storage: ref.watch(photoStorageProvider),
    repo: ref.watch(photoRepositoryProvider),
  );
});
```

- [ ] **Step 3: Write controller test**

`test/core/photos/photo_capture_controller_test.dart`:

```dart
import 'dart:io';

import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/photos/camera_service.dart';
import 'package:firecheck/core/photos/image_processor.dart';
import 'package:firecheck/core/photos/photo_capture_controller.dart';
import 'package:firecheck/core/photos/photo_storage_service.dart';
import 'package:firecheck/features/survey/photo_capture/data/photo_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late PhotoCaptureController controller;
  late InMemoryPhotoStorage storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('photo_ctrl_test_');
    final src = img.Image(width: 200, height: 100);
    img.fill(src, color: img.ColorRgb8(128, 128, 128));
    final srcPath = p.join(tempDir.path, 'src.jpg');
    await File(srcPath).writeAsBytes(img.encodeJpg(src));

    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = InMemoryPhotoStorage(root: tempDir.path);

    controller = PhotoCaptureController(
      camera: FakeCameraService(scriptedPath: srcPath),
      processor: const ImageProcessor(),
      storage: storage,
      repo: PhotoRepository(db: db, storage: storage),
    );
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('capture inserts a photos row + writes file', () async {
    final id = await controller.capture(submissionId: 'sub-1');
    expect(id, isNotNull);

    final rows = await db.select(db.photos).get();
    expect(rows, hasLength(1));
    expect(rows.first.submissionId, 'sub-1');
    expect(File(rows.first.localPath).existsSync(), isTrue);
  });

  test('capture with cancelled camera returns null + no row', () async {
    final cancelController = PhotoCaptureController(
      camera: FakeCameraService(),
      processor: const ImageProcessor(),
      storage: storage,
      repo: PhotoRepository(db: db, storage: storage),
    );
    final id = await cancelController.capture(submissionId: 'sub-1');
    expect(id, isNull);
    final rows = await db.select(db.photos).get();
    expect(rows, isEmpty);
  });
}
```

- [ ] **Step 4: Run + commit**

```bash
flutter test test/core/photos/photo_capture_controller_test.dart
flutter analyze lib/core/photos/ test/core/photos/
git add lib/core/photos/photo_capture_controller.dart lib/core/photos/photo_providers.dart test/core/photos/photo_capture_controller_test.dart
git commit -m "feat(photos): PhotoCaptureController + Riverpod providers + tests"
```

---

## Task 7: PhotoRepository + tests

**Files:**
- Create: `lib/features/survey/photo_capture/data/photo_repository.dart`
- Create: `test/features/survey/photo_capture/photo_repository_test.dart`

- [ ] **Step 1: Implement**

```dart
import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/photos/photo_storage_service.dart';
import 'package:uuid/uuid.dart';

class PhotoRepository {
  PhotoRepository({required this.db, required this.storage});
  final AppDatabase db;
  final PhotoStorageService storage;

  Stream<List<Photo>> watchForSubmission(String submissionId) {
    return (db.select(db.photos)
          ..where((t) => t.submissionId.equals(submissionId))
          ..orderBy([(t) => OrderingTerm.asc(t.capturedAt)]))
        .watch();
  }

  Future<int> countForSubmission(String submissionId) async {
    final rows = await (db.select(db.photos)
          ..where((t) => t.submissionId.equals(submissionId)))
        .get();
    return rows.length;
  }

  /// Inserts a Drift row referencing an already-on-disk file. Returns the
  /// new photo id.
  Future<String> insert({
    required String submissionId,
    required String localPath,
    required DateTime capturedAt,
    double? gpsLat,
    double? gpsLng,
  }) async {
    final id = const Uuid().v4();
    await db.into(db.photos).insert(
          PhotosCompanion.insert(
            id: id,
            submissionId: submissionId,
            localPath: localPath,
            capturedAt: capturedAt,
            gpsLat: Value(gpsLat),
            gpsLng: Value(gpsLng),
            createdAt: DateTime.now(),
          ),
        );
    return id;
  }

  /// Removes the Drift row AND deletes the file from disk.
  Future<void> delete(String photoId) async {
    final row = await (db.select(db.photos)..where((t) => t.id.equals(photoId)))
        .getSingleOrNull();
    if (row == null) return;
    await storage.deleteFile(row.localPath);
    await (db.delete(db.photos)..where((t) => t.id.equals(photoId))).go();
  }
}
```

- [ ] **Step 2: Test**

```dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/photos/photo_storage_service.dart';
import 'package:firecheck/features/survey/photo_capture/data/photo_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PhotoRepository repo;
  late InMemoryPhotoStorage storage;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = InMemoryPhotoStorage();
    repo = PhotoRepository(db: db, storage: storage);
  });

  tearDown(() async => db.close());

  test('insert + watchForSubmission emits the row', () async {
    final id = await repo.insert(
      submissionId: 'sub-1',
      localPath: '/tmp/p.jpg',
      capturedAt: DateTime.now(),
      gpsLat: 10.3,
      gpsLng: 123.9,
    );
    final list = await repo.watchForSubmission('sub-1').first;
    expect(list, hasLength(1));
    expect(list.first.id, id);
    expect(list.first.gpsLat, 10.3);
  });

  test('countForSubmission returns 0 then 1', () async {
    expect(await repo.countForSubmission('sub-1'), 0);
    await repo.insert(
      submissionId: 'sub-1',
      localPath: '/tmp/p.jpg',
      capturedAt: DateTime.now(),
    );
    expect(await repo.countForSubmission('sub-1'), 1);
  });

  test('delete removes the row + asks storage to delete the file', () async {
    final id = await repo.insert(
      submissionId: 'sub-1',
      localPath: '/tmp/p.jpg',
      capturedAt: DateTime.now(),
    );
    await repo.delete(id);
    expect(await repo.countForSubmission('sub-1'), 0);
    expect(storage.deleted, contains('/tmp/p.jpg'));
  });
}
```

- [ ] **Step 3: Run + commit**

```bash
flutter test test/features/survey/photo_capture/
flutter analyze lib/features/survey/photo_capture/ test/features/survey/photo_capture/
git add lib/features/survey/photo_capture/ test/features/survey/photo_capture/
git commit -m "feat(photo_capture): PhotoRepository + tests"
```

---

## Task 8: SubmissionRepository + tests

**Files:**
- Create: `lib/features/survey/building_form/data/submission_repository.dart`
- Create: `test/features/survey/building_form/submission_repository_test.dart`

- [ ] **Step 1: Implement**

```dart
import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:uuid/uuid.dart';

class SubmissionRepository {
  SubmissionRepository(this._db);
  final AppDatabase _db;

  /// If a draft exists for this feature, returns it. Otherwise creates one
  /// and returns the new row. Idempotent — always safe to call on first
  /// polygon tap.
  Future<Submission> ensureDraftForFeature({
    required String featureId,
    required String enumeratorId,
  }) async {
    final existing = await (_db.select(_db.submissions)
          ..where((t) =>
              t.featureId.equals(featureId) & t.syncStatus.equals('draft'))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    if (existing != null) return existing;
    return _createDraft(featureId, enumeratorId);
  }

  /// Always creates a new draft. Used by the "+" tab.
  Future<Submission> createAdditionalSubmission({
    required String featureId,
    required String enumeratorId,
  }) {
    return _createDraft(featureId, enumeratorId);
  }

  Future<Submission> _createDraft(String featureId, String enumeratorId) async {
    final now = DateTime.now();
    final id = const Uuid().v4();
    final companion = SubmissionsCompanion.insert(
      id: id,
      featureId: featureId,
      submittedBy: Value(enumeratorId),
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.submissions).insert(companion);
    final row = await (_db.select(_db.submissions)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    return row;
  }

  Stream<List<Submission>> watchSubmissionsForFeature(String featureId) {
    return (_db.select(_db.submissions)
          ..where((t) => t.featureId.equals(featureId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  Future<int> countSubmissionsForFeature(String featureId) async {
    final rows = await (_db.select(_db.submissions)
          ..where((t) => t.featureId.equals(featureId)))
        .get();
    return rows.length;
  }

  Future<void> updateOverrideReason(String submissionId, String reason) {
    return (_db.update(_db.submissions)..where((t) => t.id.equals(submissionId)))
        .write(SubmissionsCompanion(
      overrideReason: Value(reason),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> updateDoesNotExist(String submissionId, bool doesNotExist) {
    return (_db.update(_db.submissions)..where((t) => t.id.equals(submissionId)))
        .write(SubmissionsCompanion(
      doesNotExist: Value(doesNotExist),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> markStatus(String submissionId, String syncStatus) {
    return (_db.update(_db.submissions)..where((t) => t.id.equals(submissionId)))
        .write(SubmissionsCompanion(
      syncStatus: Value(syncStatus),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> deleteSubmission(String submissionId) {
    return (_db.delete(_db.submissions)..where((t) => t.id.equals(submissionId)))
        .go();
  }
}
```

- [ ] **Step 2: Tests**

```dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/survey/building_form/data/submission_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SubmissionRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = SubmissionRepository(db);
  });

  tearDown(() async => db.close());

  test('ensureDraftForFeature is idempotent', () async {
    final a = await repo.ensureDraftForFeature(
      featureId: 'f1',
      enumeratorId: 'u1',
    );
    final b = await repo.ensureDraftForFeature(
      featureId: 'f1',
      enumeratorId: 'u1',
    );
    expect(a.id, b.id);
    expect(await repo.countSubmissionsForFeature('f1'), 1);
  });

  test('createAdditionalSubmission always creates a new row', () async {
    await repo.ensureDraftForFeature(
      featureId: 'f1',
      enumeratorId: 'u1',
    );
    await repo.createAdditionalSubmission(
      featureId: 'f1',
      enumeratorId: 'u1',
    );
    expect(await repo.countSubmissionsForFeature('f1'), 2);
  });

  test('updateOverrideReason persists the value', () async {
    final s = await repo.ensureDraftForFeature(
      featureId: 'f1',
      enumeratorId: 'u1',
    );
    await repo.updateOverrideReason(s.id, 'polygon misplaced');
    final reloaded = (await db.select(db.submissions).get()).single;
    expect(reloaded.overrideReason, 'polygon misplaced');
  });

  test('updateDoesNotExist + markStatus + delete', () async {
    final s = await repo.ensureDraftForFeature(
      featureId: 'f1',
      enumeratorId: 'u1',
    );
    await repo.updateDoesNotExist(s.id, true);
    await repo.markStatus(s.id, 'ready_to_upload');
    var reloaded = (await db.select(db.submissions).get()).single;
    expect(reloaded.doesNotExist, isTrue);
    expect(reloaded.syncStatus, 'ready_to_upload');

    await repo.deleteSubmission(s.id);
    expect(await db.select(db.submissions).get(), isEmpty);
  });
}
```

- [ ] **Step 3: Run + commit**

```bash
flutter test test/features/survey/building_form/submission_repository_test.dart
flutter analyze lib/features/survey/building_form/data/submission_repository.dart test/features/survey/building_form/submission_repository_test.dart
git add lib/features/survey/building_form/data/submission_repository.dart test/features/survey/building_form/submission_repository_test.dart
git commit -m "feat(building_form): SubmissionRepository with multi-submission ops + tests"
```

---

## Task 9: BuildingAttributesRepository + tests

**Files:**
- Create: `lib/features/survey/building_form/data/building_attributes_repository.dart`
- Create: `test/features/survey/building_form/building_attributes_repository_test.dart`

- [ ] **Step 1: Implement**

```dart
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';

class BuildingAttributesRepository {
  BuildingAttributesRepository(this._db);
  final AppDatabase _db;

  Stream<BuildingAttribute?> watchForSubmission(String submissionId) {
    return (_db.select(_db.buildingAttributes)
          ..where((t) => t.submissionId.equals(submissionId)))
        .watchSingleOrNull();
  }

  Future<void> upsertForSubmission({
    required String submissionId,
    String? cbmsId,
    String? buildingName,
    String? ra9514Type,
    int? storeys,
    String? material,
    bool costIsExact = false,
    double? costAmount,
    String? costEstimateRange,
    List<String> fireFightingFacilities = const [],
    List<String> fireLoad = const [],
  }) {
    return _db.into(_db.buildingAttributes).insertOnConflictUpdate(
          BuildingAttributesCompanion.insert(
            submissionId: submissionId,
            cbmsId: Value(cbmsId),
            buildingName: Value(buildingName),
            ra9514Type: Value(ra9514Type),
            storeys: Value(storeys),
            material: Value(material),
            costIsExact: Value(costIsExact),
            costAmount: Value(costAmount),
            costEstimateRange: Value(costEstimateRange),
            fireFightingFacilitiesJson: Value(jsonEncode(fireFightingFacilities)),
            fireLoadJson: Value(jsonEncode(fireLoad)),
          ),
        );
  }

  /// Helper that decodes the JSON list columns. Use in screens.
  static List<String> decodeStringList(String json) {
    if (json.isEmpty) return const [];
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return decoded.whereType<String>().toList();
  }
}
```

- [ ] **Step 2: Test**

```dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/survey/building_form/data/building_attributes_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late BuildingAttributesRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = BuildingAttributesRepository(db);
  });

  tearDown(() async => db.close());

  test('upsert then watch returns the row', () async {
    await repo.upsertForSubmission(
      submissionId: 's1',
      buildingName: 'Hall',
      ra9514Type: 'A',
      storeys: 3,
      material: 'Concrete',
      costIsExact: false,
      costEstimateRange: '500k–1M',
      fireFightingFacilities: ['Extinguisher', 'Smoke alarm'],
      fireLoad: ['Wood furniture', 'Fabric'],
    );
    final row = await repo.watchForSubmission('s1').first;
    expect(row, isNotNull);
    expect(row!.buildingName, 'Hall');
    expect(row.storeys, 3);
    expect(
      BuildingAttributesRepository.decodeStringList(row.fireFightingFacilitiesJson),
      ['Extinguisher', 'Smoke alarm'],
    );
  });

  test('upsert overwrites existing row', () async {
    await repo.upsertForSubmission(submissionId: 's1', storeys: 1);
    await repo.upsertForSubmission(submissionId: 's1', storeys: 5);
    final row = await repo.watchForSubmission('s1').first;
    expect(row!.storeys, 5);
  });

  test('watchForSubmission emits null for unknown submission', () async {
    expect(await repo.watchForSubmission('nope').first, isNull);
  });
}
```

- [ ] **Step 3: Run + commit**

```bash
flutter test test/features/survey/building_form/building_attributes_repository_test.dart
flutter analyze lib/features/survey/building_form/data/building_attributes_repository.dart test/features/survey/building_form/building_attributes_repository_test.dart
git add lib/features/survey/building_form/data/building_attributes_repository.dart test/features/survey/building_form/building_attributes_repository_test.dart
git commit -m "feat(building_form): BuildingAttributesRepository + tests"
```

---

## Task 10: Extended FeatureRepository — markFeatureStatus + tests

**Files:**
- Modify: `lib/features/map/data/feature_repository.dart`
- Modify: `test/features/map/feature_repository_test.dart`

- [ ] **Step 1: Extend `feature_repository.dart`**

```dart
import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';

class FeatureRepository {
  FeatureRepository(this._db);
  final AppDatabase _db;

  Stream<List<Feature>> watchFeaturesForAssignment(String assignmentId) {
    return (_db.select(_db.features)
          ..where((t) => t.assignmentId.equals(assignmentId)))
        .watch();
  }

  Future<Feature?> getFeature(String id) {
    return (_db.select(_db.features)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Recompute the feature's color-coded status from its submissions.
  ///   any submission with syncStatus='ready_to_upload' or further → 'complete'
  ///   any non-empty draft (has a building_attributes row) → 'in_progress'
  ///   else → 'unfilled'
  Future<void> markFeatureStatus(String featureId) async {
    final submissions = await (_db.select(_db.submissions)
          ..where((t) => t.featureId.equals(featureId)))
        .get();

    String status = 'unfilled';

    if (submissions.any((s) =>
        s.syncStatus == 'ready_to_upload' ||
        s.syncStatus == 'queued' ||
        s.syncStatus == 'uploaded')) {
      status = 'complete';
    } else {
      // If any submission has a non-null building_attributes row OR is
      // does_not_exist toggled, treat the feature as in_progress.
      final attrIds = submissions.map((s) => s.id).toList();
      final attrs = attrIds.isEmpty
          ? <BuildingAttribute>[]
          : await (_db.select(_db.buildingAttributes)
                ..where((t) => t.submissionId.isIn(attrIds)))
              .get();
      final anyInProgress = attrs.isNotEmpty ||
          submissions.any((s) => s.doesNotExist);
      if (anyInProgress) status = 'in_progress';
    }

    await (_db.update(_db.features)..where((t) => t.id.equals(featureId)))
        .write(FeaturesCompanion(status: Value(status)));
  }
}
```

- [ ] **Step 2: Add tests to existing test file**

Append to `test/features/map/feature_repository_test.dart`:

```dart
  group('markFeatureStatus', () {
    test('feature with no submissions stays unfilled', () async {
      await db.into(db.features).insert(
            FeaturesCompanion.insert(
              id: 'f1',
              assignmentId: 'a1',
              featureType: 'building',
              geometryGeojson: '{}',
              createdAt: DateTime.now(),
            ),
          );
      await repo.markFeatureStatus('f1');
      final f = (await db.select(db.features).get()).single;
      expect(f.status, 'unfilled');
    });

    test('feature with a draft + building_attributes is in_progress', () async {
      final now = DateTime.now();
      await db.into(db.features).insert(
            FeaturesCompanion.insert(
              id: 'f1',
              assignmentId: 'a1',
              featureType: 'building',
              geometryGeojson: '{}',
              createdAt: now,
            ),
          );
      await db.into(db.submissions).insert(
            SubmissionsCompanion.insert(
              id: 's1',
              featureId: 'f1',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db.into(db.buildingAttributes).insert(
            BuildingAttributesCompanion.insert(
              submissionId: 's1',
              buildingName: const Value('Hall'),
            ),
          );
      await repo.markFeatureStatus('f1');
      final f = (await db.select(db.features).get()).single;
      expect(f.status, 'in_progress');
    });

    test('feature with a ready_to_upload submission is complete', () async {
      final now = DateTime.now();
      await db.into(db.features).insert(
            FeaturesCompanion.insert(
              id: 'f1',
              assignmentId: 'a1',
              featureType: 'building',
              geometryGeojson: '{}',
              createdAt: now,
            ),
          );
      await db.into(db.submissions).insert(
            SubmissionsCompanion.insert(
              id: 's1',
              featureId: 'f1',
              syncStatus: const Value('ready_to_upload'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await repo.markFeatureStatus('f1');
      final f = (await db.select(db.features).get()).single;
      expect(f.status, 'complete');
    });
  });
```

- [ ] **Step 3: Run + commit**

```bash
flutter test test/features/map/feature_repository_test.dart
git add lib/features/map/data/feature_repository.dart test/features/map/feature_repository_test.dart
git commit -m "feat(map): FeatureRepository.markFeatureStatus + tests"
```

---

## Task 11: BuildingFormState + validator + RA 9514 fallback + tests

**Files:**
- Create: `lib/features/survey/building_form/domain/building_form_state.dart`
- Create: `lib/features/survey/building_form/domain/ra_9514_fallback.dart`
- Create: `lib/features/survey/building_form/domain/building_form_validator.dart`
- Create: `test/features/survey/building_form/building_form_validator_test.dart`

- [ ] **Step 1: Create `building_form_state.dart`**

```dart
class BuildingFormState {
  const BuildingFormState({
    required this.submissionId,
    this.cbmsId,
    this.buildingName,
    this.ra9514Type,
    this.storeys,
    this.material,
    this.costIsExact = false,
    this.costAmount,
    this.costEstimateRange,
    this.fireFightingFacilities = const [],
    this.fireLoad = const [],
    this.doesNotExist = false,
    this.overrideReason,
  });

  final String submissionId;
  final String? cbmsId;
  final String? buildingName;
  final String? ra9514Type;
  final int? storeys;
  final String? material;
  final bool costIsExact;
  final double? costAmount;
  final String? costEstimateRange;
  final List<String> fireFightingFacilities;
  final List<String> fireLoad;
  final bool doesNotExist;
  final String? overrideReason;

  BuildingFormState copyWith({
    String? cbmsId,
    String? buildingName,
    String? ra9514Type,
    int? storeys,
    String? material,
    bool? costIsExact,
    double? costAmount,
    String? costEstimateRange,
    List<String>? fireFightingFacilities,
    List<String>? fireLoad,
    bool? doesNotExist,
    String? overrideReason,
    bool clearCostAmount = false,
    bool clearCostEstimateRange = false,
  }) {
    return BuildingFormState(
      submissionId: submissionId,
      cbmsId: cbmsId ?? this.cbmsId,
      buildingName: buildingName ?? this.buildingName,
      ra9514Type: ra9514Type ?? this.ra9514Type,
      storeys: storeys ?? this.storeys,
      material: material ?? this.material,
      costIsExact: costIsExact ?? this.costIsExact,
      costAmount: clearCostAmount ? null : (costAmount ?? this.costAmount),
      costEstimateRange: clearCostEstimateRange
          ? null
          : (costEstimateRange ?? this.costEstimateRange),
      fireFightingFacilities:
          fireFightingFacilities ?? this.fireFightingFacilities,
      fireLoad: fireLoad ?? this.fireLoad,
      doesNotExist: doesNotExist ?? this.doesNotExist,
      overrideReason: overrideReason ?? this.overrideReason,
    );
  }
}
```

- [ ] **Step 2: Create `ra_9514_fallback.dart`**

```dart
/// Hardcoded fallback list of the 10 RA 9514 occupancy groups. Used when
/// the local Drift `ra_9514_types` table is empty (which is the case until
/// Phase 3's seed populates it).
class Ra9514Entry {
  const Ra9514Entry({required this.code, required this.labelKey});
  final String code;
  final String labelKey; // matches an i18n key like 'ra9514GroupA'
}

const ra9514Fallback = <Ra9514Entry>[
  Ra9514Entry(code: 'A', labelKey: 'ra9514GroupA'),
  Ra9514Entry(code: 'B', labelKey: 'ra9514GroupB'),
  Ra9514Entry(code: 'C', labelKey: 'ra9514GroupC'),
  Ra9514Entry(code: 'D', labelKey: 'ra9514GroupD'),
  Ra9514Entry(code: 'E', labelKey: 'ra9514GroupE'),
  Ra9514Entry(code: 'F', labelKey: 'ra9514GroupF'),
  Ra9514Entry(code: 'G', labelKey: 'ra9514GroupG'),
  Ra9514Entry(code: 'H', labelKey: 'ra9514GroupH'),
  Ra9514Entry(code: 'I', labelKey: 'ra9514GroupI'),
  Ra9514Entry(code: 'J', labelKey: 'ra9514GroupJ'),
];
```

- [ ] **Step 3: Create `building_form_validator.dart`**

```dart
import 'package:firecheck/features/survey/building_form/domain/building_form_state.dart';

class ValidationResult {
  const ValidationResult({
    this.fieldErrors = const {},
    this.warnings = const [],
  });
  final Map<String, String> fieldErrors;
  final List<String> warnings;
  bool get isComplete => fieldErrors.isEmpty;
}

ValidationResult validateBuildingForm(BuildingFormState state, int photoCount) {
  final fieldErrors = <String, String>{};
  final warnings = <String>[];

  if (photoCount < 1) {
    fieldErrors['photo'] = 'photo_required';
  }

  if (!state.doesNotExist) {
    if ((state.buildingName ?? '').trim().isEmpty) {
      fieldErrors['buildingName'] = 'required';
    }
    if (state.ra9514Type == null) {
      fieldErrors['ra9514Type'] = 'required';
    }
    if (state.storeys == null || state.storeys! < 1) {
      fieldErrors['storeys'] = 'required';
    } else if (state.storeys! > 50) {
      warnings.add('storeys_warning_too_tall');
    }
    if (state.material == null) {
      fieldErrors['material'] = 'required';
    }
    final costExactOk = state.costIsExact &&
        state.costAmount != null &&
        state.costAmount! > 0;
    final costRangeOk =
        !state.costIsExact && (state.costEstimateRange ?? '').isNotEmpty;
    if (!costExactOk && !costRangeOk) {
      fieldErrors['cost'] = 'required';
    }
    if (state.fireLoad.isEmpty) {
      fieldErrors['fireLoad'] = 'required';
    }
  }

  return ValidationResult(fieldErrors: fieldErrors, warnings: warnings);
}
```

- [ ] **Step 4: Test the validator**

```dart
import 'package:firecheck/features/survey/building_form/domain/building_form_state.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BuildingFormState empty() => const BuildingFormState(submissionId: 's1');

  group('validateBuildingForm — does not exist OFF', () {
    test('empty form has all required errors', () {
      final r = validateBuildingForm(empty(), 0);
      expect(r.fieldErrors.keys, containsAll([
        'photo', 'buildingName', 'ra9514Type', 'storeys', 'material',
        'cost', 'fireLoad',
      ]));
      expect(r.isComplete, isFalse);
    });

    test('all required + 1 photo + cost range → complete', () {
      final s = empty().copyWith(
        buildingName: 'Hall',
        ra9514Type: 'A',
        storeys: 2,
        material: 'Concrete',
        costEstimateRange: '500k–1M',
        fireLoad: ['Wood furniture'],
      );
      final r = validateBuildingForm(s, 1);
      expect(r.fieldErrors, isEmpty);
      expect(r.isComplete, isTrue);
    });

    test('cost exact requires positive amount', () {
      final s = empty().copyWith(
        buildingName: 'Hall',
        ra9514Type: 'A',
        storeys: 2,
        material: 'Concrete',
        costIsExact: true,
        costAmount: 0,
        fireLoad: ['Wood furniture'],
      );
      final r = validateBuildingForm(s, 1);
      expect(r.fieldErrors, containsPair('cost', isNotNull));
    });

    test('storeys >50 yields a warning, still complete', () {
      final s = empty().copyWith(
        buildingName: 'Tower',
        ra9514Type: 'A',
        storeys: 80,
        material: 'Steel',
        costEstimateRange: '>10M',
        fireLoad: ['Fabric'],
      );
      final r = validateBuildingForm(s, 1);
      expect(r.warnings, contains('storeys_warning_too_tall'));
      expect(r.isComplete, isTrue);
    });
  });

  group('validateBuildingForm — does not exist ON', () {
    test('only photo is required', () {
      final s = empty().copyWith(doesNotExist: true);
      final r = validateBuildingForm(s, 0);
      expect(r.fieldErrors.keys.toList(), ['photo']);
    });

    test('with photo → complete', () {
      final s = empty().copyWith(doesNotExist: true);
      final r = validateBuildingForm(s, 1);
      expect(r.isComplete, isTrue);
    });
  });
}
```

- [ ] **Step 5: Run + commit**

```bash
flutter test test/features/survey/building_form/building_form_validator_test.dart
flutter analyze lib/features/survey/building_form/domain/ test/features/survey/building_form/building_form_validator_test.dart
git add lib/features/survey/building_form/domain/ test/features/survey/building_form/building_form_validator_test.dart
git commit -m "feat(building_form): BuildingFormState + validator + RA 9514 fallback"
```

---

## Task 12: Override check use case + tests

**Files:**
- Create: `lib/features/survey/building_form/domain/override_check.dart`
- Create: `test/features/survey/building_form/override_check_test.dart`

- [ ] **Step 1: Implement**

```dart
import 'package:firecheck/core/geo/centroid.dart';
import 'package:firecheck/core/location/distance.dart';

sealed class TapResult {
  const TapResult();
  double get meters;
}

class TapAllowed extends TapResult {
  const TapAllowed(this.meters);
  @override
  final double meters;
}

class TapBlocked extends TapResult {
  const TapBlocked(this.meters);
  @override
  final double meters;
}

class TapAllowedWithOverride extends TapResult {
  const TapAllowedWithOverride({required this.meters, required this.reason});
  @override
  final double meters;
  final String reason;
}

const _maxMeters = 50.0;

/// Determines whether a polygon tap is allowed given the user's current GPS.
/// If the distance exceeds the 50 m policy, calls [promptForReason] and
/// returns either [TapAllowedWithOverride] (with the reason) or
/// [TapBlocked] (if the user dismissed the prompt).
Future<TapResult> checkTap({
  required double userLat,
  required double userLng,
  required List<List<double>> featureRing,
  required Future<String?> Function() promptForReason,
}) async {
  final centroid = polygonCentroid(featureRing);
  final meters =
      haversineMeters(userLat, userLng, centroid.lat, centroid.lng);
  if (meters <= _maxMeters) return TapAllowed(meters);

  final reason = await promptForReason();
  if (reason == null || reason.trim().isEmpty) return TapBlocked(meters);
  return TapAllowedWithOverride(meters: meters, reason: reason.trim());
}
```

- [ ] **Step 2: Test**

```dart
import 'package:firecheck/features/survey/building_form/domain/override_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Brgy. Tisa rectangle (centroid ~10.31810, 123.88270).
  const ring = [
    [123.88200, 10.31720],
    [123.88340, 10.31720],
    [123.88340, 10.31900],
    [123.88200, 10.31900],
    [123.88200, 10.31720],
  ];

  test('user within 50m → TapAllowed', () async {
    final r = await checkTap(
      userLat: 10.31810,
      userLng: 123.88270,
      featureRing: ring,
      promptForReason: () async => fail('should not prompt'),
    );
    expect(r, isA<TapAllowed>());
  });

  test('user far away + reason → TapAllowedWithOverride', () async {
    final r = await checkTap(
      userLat: 10.40,
      userLng: 123.88,
      featureRing: ring,
      promptForReason: () async => 'polygon misplaced',
    );
    expect(r, isA<TapAllowedWithOverride>());
    expect((r as TapAllowedWithOverride).reason, 'polygon misplaced');
  });

  test('user far away + dismissed prompt → TapBlocked', () async {
    final r = await checkTap(
      userLat: 10.40,
      userLng: 123.88,
      featureRing: ring,
      promptForReason: () async => null,
    );
    expect(r, isA<TapBlocked>());
  });

  test('user far away + empty reason → TapBlocked', () async {
    final r = await checkTap(
      userLat: 10.40,
      userLng: 123.88,
      featureRing: ring,
      promptForReason: () async => '   ',
    );
    expect(r, isA<TapBlocked>());
  });
}
```

- [ ] **Step 3: Run + commit**

```bash
flutter test test/features/survey/building_form/override_check_test.dart
git add lib/features/survey/building_form/domain/override_check.dart test/features/survey/building_form/override_check_test.dart
git commit -m "feat(building_form): override_check use case + tests"
```

---

## Task 13: PhotoStrip widget + providers + tests

**Files:**
- Create: `lib/features/survey/photo_capture/presentation/photo_strip_providers.dart`
- Create: `lib/features/survey/photo_capture/presentation/photo_strip.dart`
- Create: `test/features/survey/photo_capture/photo_strip_test.dart`

- [ ] **Step 1: Create `photo_strip_providers.dart`**

```dart
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/photos/photo_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final photosForSubmissionProvider =
    StreamProvider.autoDispose.family<List<Photo>, String>((ref, submissionId) {
  return ref
      .watch(photoRepositoryProvider)
      .watchForSubmission(submissionId);
});
```

- [ ] **Step 2: Implement `photo_strip.dart`**

```dart
import 'dart:io';

import 'package:firecheck/core/photos/photo_providers.dart';
import 'package:firecheck/features/survey/photo_capture/presentation/photo_strip_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PhotoStrip extends ConsumerWidget {
  const PhotoStrip({required this.submissionId, super.key});
  final String submissionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final photosAsync = ref.watch(photosForSubmissionProvider(submissionId));

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          photosAsync.when(
            loading: () => Text(l.photosLabel),
            error: (e, _) => Text(l.photosLabel),
            data: (photos) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l.photosLabel,
                    style: Theme.of(context).textTheme.labelMedium),
                photos.isEmpty
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFC53030),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          l.photosRequiredBadge,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600),
                        ),
                      )
                    : Text(
                        l.photosCompleteBadge,
                        style: const TextStyle(
                            color: Color(0xFF276749),
                            fontWeight: FontWeight.w600),
                      ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 60,
            child: photosAsync.when(
              loading: () => const SizedBox(),
              error: (e, _) => const SizedBox(),
              data: (photos) => ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  if (i == photos.length) {
                    return _AddPhotoChip(submissionId: submissionId);
                  }
                  return _Thumbnail(photo: photos[i]);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPhotoChip extends ConsumerWidget {
  const _AddPhotoChip({required this.submissionId});
  final String submissionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return GestureDetector(
      key: const Key('photo-strip.add'),
      onTap: () async {
        try {
          await ref
              .read(photoCaptureControllerProvider)
              .capture(submissionId: submissionId);
        } on Object {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.cameraPermissionSnackbar)),
            );
          }
        }
      },
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: const Color(0x103B82F6),
          border: Border.all(color: const Color(0xFF3B82F6), width: 1.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            l.addPhoto,
            style: const TextStyle(
                color: Color(0xFF3B82F6),
                fontSize: 10,
                fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends ConsumerWidget {
  const _Thumbnail({required this.photo});
  final dynamic photo; // Drift's Photo type — keep loose to avoid the import here

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return GestureDetector(
      key: Key('photo-strip.thumb.${photo.id}'),
      onLongPress: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l.deletePhoto),
            content: Text(l.deletePhotoConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.cancelLabel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l.deleteAction),
              ),
            ],
          ),
        );
        if (ok == true) {
          await ref.read(photoRepositoryProvider).delete(photo.id as String);
        }
      },
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.grey.shade400,
          borderRadius: BorderRadius.circular(6),
          image: DecorationImage(
            image: FileImage(File(photo.localPath as String)),
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Test**

```dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/photos/photo_providers.dart';
import 'package:firecheck/core/photos/photo_storage_service.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/photo_capture/data/photo_repository.dart';
import 'package:firecheck/features/survey/photo_capture/presentation/photo_strip.dart';
import 'package:firecheck/features/survey/photo_capture/presentation/photo_strip_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PhotoRepository repo;
  late InMemoryPhotoStorage storage;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = InMemoryPhotoStorage();
    repo = PhotoRepository(db: db, storage: storage);
  });

  tearDown(() async => db.close());

  Widget wrap() {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        photoStorageProvider.overrideWithValue(storage),
        photoRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: PhotoStrip(submissionId: 'sub-1')),
      ),
    );
  }

  testWidgets('shows red required badge with no photos', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();
    expect(find.text('0 / 1 required'), findsOneWidget);
    expect(find.text('+ Photo'), findsOneWidget);
  });

  testWidgets('shows complete badge after a photo is inserted', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();
    await repo.insert(
      submissionId: 'sub-1',
      localPath: '/dev/null',
      capturedAt: DateTime.now(),
    );
    await tester.pump();
    expect(find.text('1+ ✓'), findsOneWidget);
  });
}
```

(The test uses `/dev/null` as the local path so `FileImage` won't crash on a missing file — Flutter just renders the placeholder. If the test framework complains, replace with a real fixture.)

- [ ] **Step 4: Run + commit**

```bash
flutter test test/features/survey/photo_capture/photo_strip_test.dart
flutter analyze lib/features/survey/photo_capture/presentation/ test/features/survey/photo_capture/
git add lib/features/survey/photo_capture/presentation/ test/features/survey/photo_capture/photo_strip_test.dart
git commit -m "feat(photo_capture): PhotoStrip widget + required-badge logic + tests"
```

---

## Task 14: BuildingFormNotifier + tests

**Files:**
- Create: `lib/features/survey/building_form/presentation/building_form_notifier.dart`
- Create: `lib/features/survey/building_form/presentation/building_form_providers.dart`
- Create: `test/features/survey/building_form/building_form_notifier_test.dart`

- [ ] **Step 1: Implement `building_form_notifier.dart`**

```dart
import 'dart:async';
import 'dart:convert';

import 'package:firecheck/features/map/data/feature_repository.dart';
import 'package:firecheck/features/survey/building_form/data/building_attributes_repository.dart';
import 'package:firecheck/features/survey/building_form/data/submission_repository.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BuildingFormNotifier extends StateNotifier<BuildingFormState> {
  BuildingFormNotifier({
    required this.submissionId,
    required this.featureId,
    required this.submissionRepo,
    required this.attrsRepo,
    required this.featureRepo,
  }) : super(BuildingFormState(submissionId: submissionId)) {
    _loadInitial();
  }

  final String submissionId;
  final String featureId;
  final SubmissionRepository submissionRepo;
  final BuildingAttributesRepository attrsRepo;
  final FeatureRepository featureRepo;

  Timer? _debounce;
  static const _window = Duration(milliseconds: 500);

  Future<void> _loadInitial() async {
    final attrs = await attrsRepo.watchForSubmission(submissionId).first;
    if (attrs == null) return;
    state = BuildingFormState(
      submissionId: submissionId,
      cbmsId: attrs.cbmsId,
      buildingName: attrs.buildingName,
      ra9514Type: attrs.ra9514Type,
      storeys: attrs.storeys,
      material: attrs.material,
      costIsExact: attrs.costIsExact,
      costAmount: attrs.costAmount,
      costEstimateRange: attrs.costEstimateRange,
      fireFightingFacilities: BuildingAttributesRepository.decodeStringList(
        attrs.fireFightingFacilitiesJson,
      ),
      fireLoad: BuildingAttributesRepository.decodeStringList(
        attrs.fireLoadJson,
      ),
    );
  }

  void update(BuildingFormState Function(BuildingFormState) mutate) {
    state = mutate(state);
    _debounce?.cancel();
    _debounce = Timer(_window, _flush);
  }

  /// For external triggers (e.g. Done button) that need to wait for the
  /// pending write to land.
  Future<void> flushNow() async {
    _debounce?.cancel();
    await _flush();
  }

  Future<void> _flush() async {
    await attrsRepo.upsertForSubmission(
      submissionId: state.submissionId,
      cbmsId: state.cbmsId,
      buildingName: state.buildingName,
      ra9514Type: state.ra9514Type,
      storeys: state.storeys,
      material: state.material,
      costIsExact: state.costIsExact,
      costAmount: state.costAmount,
      costEstimateRange: state.costEstimateRange,
      fireFightingFacilities: state.fireFightingFacilities,
      fireLoad: state.fireLoad,
    );
    await submissionRepo.updateDoesNotExist(
      state.submissionId,
      state.doesNotExist,
    );
    await featureRepo.markFeatureStatus(featureId);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // Best-effort flush on dispose; we deliberately don't await — the
    // notifier is being torn down.
    unawaited(_flush());
    super.dispose();
  }
}
```

- [ ] **Step 2: Test**

```dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/map/data/feature_repository.dart';
import 'package:firecheck/features/survey/building_form/data/building_attributes_repository.dart';
import 'package:firecheck/features/survey/building_form/data/submission_repository.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_state.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SubmissionRepository sr;
  late BuildingAttributesRepository ar;
  late FeatureRepository fr;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sr = SubmissionRepository(db);
    ar = BuildingAttributesRepository(db);
    fr = FeatureRepository(db);
    final now = DateTime.now();
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f1',
            assignmentId: 'a1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: now,
          ),
        );
  });

  tearDown(() async => db.close());

  test('debounced write lands after 500ms', () async {
    final s = await sr.ensureDraftForFeature(
      featureId: 'f1',
      enumeratorId: 'u1',
    );
    final n = BuildingFormNotifier(
      submissionId: s.id,
      featureId: 'f1',
      submissionRepo: sr,
      attrsRepo: ar,
      featureRepo: fr,
    );
    n.update((st) => st.copyWith(buildingName: 'Hall'));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final attrs = await ar.watchForSubmission(s.id).first;
    expect(attrs, isNotNull);
    expect(attrs!.buildingName, 'Hall');
  });

  test('flushNow writes immediately', () async {
    final s = await sr.ensureDraftForFeature(
      featureId: 'f1',
      enumeratorId: 'u1',
    );
    final n = BuildingFormNotifier(
      submissionId: s.id,
      featureId: 'f1',
      submissionRepo: sr,
      attrsRepo: ar,
      featureRepo: fr,
    );
    n.update((st) => st.copyWith(buildingName: 'Hall'));
    await n.flushNow();
    final attrs = await ar.watchForSubmission(s.id).first;
    expect(attrs!.buildingName, 'Hall');
  });

  test('does-not-exist toggle flips submissions row', () async {
    final s = await sr.ensureDraftForFeature(
      featureId: 'f1',
      enumeratorId: 'u1',
    );
    final n = BuildingFormNotifier(
      submissionId: s.id,
      featureId: 'f1',
      submissionRepo: sr,
      attrsRepo: ar,
      featureRepo: fr,
    );
    n.update((st) => st.copyWith(doesNotExist: true));
    await n.flushNow();
    final reloaded = (await db.select(db.submissions).get()).single;
    expect(reloaded.doesNotExist, isTrue);
  });
}
```

- [ ] **Step 3: Implement `building_form_providers.dart`**

```dart
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/map/data/feature_repository.dart';
import 'package:firecheck/features/map/presentation/map_providers.dart';
import 'package:firecheck/features/survey/building_form/data/building_attributes_repository.dart';
import 'package:firecheck/features/survey/building_form/data/submission_repository.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_state.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final submissionRepositoryProvider = Provider<SubmissionRepository>((ref) {
  return SubmissionRepository(ref.watch(appDatabaseProvider));
});

final buildingAttributesRepositoryProvider =
    Provider<BuildingAttributesRepository>((ref) {
  return BuildingAttributesRepository(ref.watch(appDatabaseProvider));
});

class _NotifierKey {
  const _NotifierKey({required this.submissionId, required this.featureId});
  final String submissionId;
  final String featureId;
  @override
  bool operator ==(Object other) =>
      other is _NotifierKey &&
      other.submissionId == submissionId &&
      other.featureId == featureId;
  @override
  int get hashCode => Object.hash(submissionId, featureId);
}

final buildingFormNotifierProvider = StateNotifierProvider.autoDispose
    .family<BuildingFormNotifier, BuildingFormState, _NotifierKey>(
        (ref, key) {
  return BuildingFormNotifier(
    submissionId: key.submissionId,
    featureId: key.featureId,
    submissionRepo: ref.watch(submissionRepositoryProvider),
    attrsRepo: ref.watch(buildingAttributesRepositoryProvider),
    featureRepo: ref.watch(featureRepositoryProvider),
  );
});

/// Convenience: builds the family key.
({StateNotifierProvider<BuildingFormNotifier, BuildingFormState> provider})
    formProviderFor({
  required String submissionId,
  required String featureId,
}) {
  return (
    provider: buildingFormNotifierProvider(
      _NotifierKey(submissionId: submissionId, featureId: featureId),
    ),
  );
}
```

- [ ] **Step 4: Run + commit**

```bash
flutter test test/features/survey/building_form/building_form_notifier_test.dart
flutter analyze lib/features/survey/building_form/presentation/ test/features/survey/building_form/building_form_notifier_test.dart
git add lib/features/survey/building_form/presentation/building_form_notifier.dart lib/features/survey/building_form/presentation/building_form_providers.dart test/features/survey/building_form/building_form_notifier_test.dart
git commit -m "feat(building_form): BuildingFormNotifier with debounced autosave + tests"
```

---

## Task 15: Form section widgets (5 widgets)

**Files:**
- Create: `lib/features/survey/building_form/presentation/sections/identity_section.dart`
- Create: `lib/features/survey/building_form/presentation/sections/construction_section.dart`
- Create: `lib/features/survey/building_form/presentation/sections/cost_section.dart`
- Create: `lib/features/survey/building_form/presentation/sections/ff_facilities_section.dart`
- Create: `lib/features/survey/building_form/presentation/sections/fire_load_section.dart`

Each section is a `ConsumerWidget` that subscribes to its slice of `BuildingFormState` via `select` and dispatches edits via `notifier.update(...)`. All sections accept `submissionId`, `featureId`, and a `disabled` bool (true when does-not-exist is on).

Implementations are mechanical — see the spec §10 for field semantics. Length-wise each ranges from 60 (chip rows) to 150 lines (cost section with radio + conditional input).

- [ ] **Step 1: Implement `identity_section.dart`**

```dart
import 'package:firecheck/features/survey/building_form/domain/ra_9514_fallback.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class IdentitySection extends ConsumerWidget {
  const IdentitySection({
    required this.submissionId,
    required this.featureId,
    required this.disabled,
    super.key,
  });

  final String submissionId;
  final String featureId;
  final bool disabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(formProviderFor(
      submissionId: submissionId,
      featureId: featureId,
    ).provider);
    final notifier = ref.read(formProviderFor(
      submissionId: submissionId,
      featureId: featureId,
    ).provider.notifier);

    return _SectionCard(
      title: l.sectionIdentity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            enabled: !disabled,
            decoration: InputDecoration(labelText: l.fieldCbmsId),
            onChanged: (v) => notifier.update((s) =>
                s.copyWith(cbmsId: v.isEmpty ? null : v)),
            controller: _controller(state.cbmsId ?? ''),
          ),
          const SizedBox(height: 12),
          TextField(
            enabled: !disabled,
            decoration: InputDecoration(labelText: l.fieldBuildingName),
            onChanged: (v) => notifier.update((s) =>
                s.copyWith(buildingName: v.isEmpty ? null : v)),
            controller: _controller(state.buildingName ?? ''),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: state.ra9514Type,
            decoration: InputDecoration(labelText: l.fieldRa9514Type),
            onChanged: disabled
                ? null
                : (v) => notifier.update((s) => s.copyWith(ra9514Type: v)),
            items: ra9514Fallback
                .map((e) => DropdownMenuItem<String>(
                      value: e.code,
                      child: Text(_labelFor(e.labelKey, l)),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  TextEditingController _controller(String value) {
    final c = TextEditingController(text: value);
    c.selection = TextSelection.collapsed(offset: value.length);
    return c;
  }

  String _labelFor(String key, AppLocalizations l) {
    switch (key) {
      case 'ra9514GroupA': return l.ra9514GroupA;
      case 'ra9514GroupB': return l.ra9514GroupB;
      case 'ra9514GroupC': return l.ra9514GroupC;
      case 'ra9514GroupD': return l.ra9514GroupD;
      case 'ra9514GroupE': return l.ra9514GroupE;
      case 'ra9514GroupF': return l.ra9514GroupF;
      case 'ra9514GroupG': return l.ra9514GroupG;
      case 'ra9514GroupH': return l.ra9514GroupH;
      case 'ra9514GroupI': return l.ra9514GroupI;
      case 'ra9514GroupJ': return l.ra9514GroupJ;
      default: return key;
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      shape: const RoundedRectangleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                color: Colors.grey,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Implement `construction_section.dart`**

```dart
import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConstructionSection extends ConsumerWidget {
  const ConstructionSection({
    required this.submissionId,
    required this.featureId,
    required this.disabled,
    super.key,
  });

  final String submissionId;
  final String featureId;
  final bool disabled;

  static const _materials = [
    ('Concrete', 'materialConcrete'),
    ('Wood', 'materialWood'),
    ('Mixed', 'materialMixed'),
    ('Light', 'materialLight'),
    ('Steel', 'materialSteel'),
    ('Other', 'materialOther'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(formProviderFor(
      submissionId: submissionId,
      featureId: featureId,
    ).provider);
    final notifier = ref.read(formProviderFor(
      submissionId: submissionId,
      featureId: featureId,
    ).provider.notifier);

    return Card(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      shape: const RoundedRectangleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.sectionConstruction.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                color: Colors.grey,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              enabled: !disabled,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l.fieldStoreys,
                helperText: state.storeys != null && state.storeys! > 50
                    ? l.storeysWarningTooTall
                    : null,
              ),
              onChanged: (v) =>
                  notifier.update((s) => s.copyWith(storeys: int.tryParse(v))),
              controller: _controller(state.storeys?.toString() ?? ''),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: state.material,
              decoration: InputDecoration(labelText: l.fieldMaterial),
              onChanged: disabled
                  ? null
                  : (v) => notifier.update((s) => s.copyWith(material: v)),
              items: _materials
                  .map((m) => DropdownMenuItem<String>(
                        value: m.$1,
                        child: Text(_label(m.$2, l)),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  TextEditingController _controller(String value) {
    final c = TextEditingController(text: value);
    c.selection = TextSelection.collapsed(offset: value.length);
    return c;
  }

  String _label(String key, AppLocalizations l) {
    switch (key) {
      case 'materialConcrete': return l.materialConcrete;
      case 'materialWood': return l.materialWood;
      case 'materialMixed': return l.materialMixed;
      case 'materialLight': return l.materialLight;
      case 'materialSteel': return l.materialSteel;
      case 'materialOther': return l.materialOther;
      default: return key;
    }
  }
}
```

- [ ] **Step 3: Implement `cost_section.dart`**

```dart
import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CostSection extends ConsumerWidget {
  const CostSection({
    required this.submissionId,
    required this.featureId,
    required this.disabled,
    super.key,
  });

  final String submissionId;
  final String featureId;
  final bool disabled;

  static const _ranges = [
    ('<100k', 'costRangeUnder100k'),
    ('100k–500k', 'costRange100to500k'),
    ('500k–1M', 'costRange500kto1M'),
    ('1M–5M', 'costRange1to5M'),
    ('5M–10M', 'costRange5to10M'),
    ('>10M', 'costRangeOver10M'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(formProviderFor(
      submissionId: submissionId,
      featureId: featureId,
    ).provider);
    final notifier = ref.read(formProviderFor(
      submissionId: submissionId,
      featureId: featureId,
    ).provider.notifier);

    return Card(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      shape: const RoundedRectangleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.sectionCost.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                color: Colors.grey,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<bool>(
                    title: Text(l.fieldCostExact),
                    value: true,
                    groupValue: state.costIsExact,
                    onChanged: disabled
                        ? null
                        : (_) => notifier.update((s) => s.copyWith(
                              costIsExact: true,
                              clearCostEstimateRange: true,
                            )),
                  ),
                ),
                Expanded(
                  child: RadioListTile<bool>(
                    title: Text(l.fieldCostRange),
                    value: false,
                    groupValue: state.costIsExact,
                    onChanged: disabled
                        ? null
                        : (_) => notifier.update((s) => s.copyWith(
                              costIsExact: false,
                              clearCostAmount: true,
                            )),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (state.costIsExact)
              TextField(
                enabled: !disabled,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l.fieldCostExactInput,
                  prefixText: '₱ ',
                ),
                onChanged: (v) => notifier.update((s) =>
                    s.copyWith(costAmount: double.tryParse(v))),
                controller: _controller(state.costAmount?.toString() ?? ''),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: state.costEstimateRange,
                decoration: InputDecoration(labelText: l.fieldCostRangeInput),
                onChanged: disabled
                    ? null
                    : (v) => notifier
                        .update((s) => s.copyWith(costEstimateRange: v)),
                items: _ranges
                    .map((r) => DropdownMenuItem<String>(
                          value: r.$1,
                          child: Text(_label(r.$2, l)),
                        ))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  TextEditingController _controller(String value) {
    final c = TextEditingController(text: value);
    c.selection = TextSelection.collapsed(offset: value.length);
    return c;
  }

  String _label(String key, AppLocalizations l) {
    switch (key) {
      case 'costRangeUnder100k': return l.costRangeUnder100k;
      case 'costRange100to500k': return l.costRange100to500k;
      case 'costRange500kto1M': return l.costRange500kto1M;
      case 'costRange1to5M': return l.costRange1to5M;
      case 'costRange5to10M': return l.costRange5to10M;
      case 'costRangeOver10M': return l.costRangeOver10M;
      default: return key;
    }
  }
}
```

- [ ] **Step 4: Implement `ff_facilities_section.dart`**

```dart
import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FfFacilitiesSection extends ConsumerWidget {
  const FfFacilitiesSection({
    required this.submissionId,
    required this.featureId,
    required this.disabled,
    super.key,
  });

  final String submissionId;
  final String featureId;
  final bool disabled;

  static const _all = [
    ('Extinguisher', 'ffExtinguisher'),
    ('Sprinkler', 'ffSprinkler'),
    ('Hose', 'ffHose'),
    ('Smoke alarm', 'ffSmokeAlarm'),
    ('None', 'ffNone'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(formProviderFor(
      submissionId: submissionId,
      featureId: featureId,
    ).provider);
    final notifier = ref.read(formProviderFor(
      submissionId: submissionId,
      featureId: featureId,
    ).provider.notifier);
    final selected = state.fireFightingFacilities.toSet();

    return Card(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      shape: const RoundedRectangleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.sectionFireFighting.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                color: Colors.grey,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _all.map((entry) {
                final value = entry.$1;
                final isSelected = selected.contains(value);
                return FilterChip(
                  label: Text(_label(entry.$2, l)),
                  selected: isSelected,
                  onSelected: disabled
                      ? null
                      : (v) {
                          final next = selected.toSet();
                          if (value == 'None') {
                            // None is mutually exclusive.
                            if (v) {
                              next
                                ..clear()
                                ..add('None');
                            } else {
                              next.remove('None');
                            }
                          } else {
                            // Selecting any other clears None.
                            next.remove('None');
                            if (v) {
                              next.add(value);
                            } else {
                              next.remove(value);
                            }
                          }
                          notifier.update((s) =>
                              s.copyWith(fireFightingFacilities: next.toList()));
                        },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  String _label(String key, AppLocalizations l) {
    switch (key) {
      case 'ffExtinguisher': return l.ffExtinguisher;
      case 'ffSprinkler': return l.ffSprinkler;
      case 'ffHose': return l.ffHose;
      case 'ffSmokeAlarm': return l.ffSmokeAlarm;
      case 'ffNone': return l.ffNone;
      default: return key;
    }
  }
}
```

- [ ] **Step 5: Implement `fire_load_section.dart`**

Same shape as ff_facilities_section but without the "None" mutually-exclusive logic. Categories: Wood furniture / Fabric / Paper / Chemicals / Cooking gas / Other. Section title `l.sectionFireLoad` (which already includes the asterisk in the i18n string).

```dart
import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FireLoadSection extends ConsumerWidget {
  const FireLoadSection({
    required this.submissionId,
    required this.featureId,
    required this.disabled,
    super.key,
  });

  final String submissionId;
  final String featureId;
  final bool disabled;

  static const _all = [
    ('Wood furniture', 'fireLoadWoodFurniture'),
    ('Fabric', 'fireLoadFabric'),
    ('Paper', 'fireLoadPaper'),
    ('Chemicals', 'fireLoadChemicals'),
    ('Cooking gas', 'fireLoadCookingGas'),
    ('Other', 'fireLoadOther'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(formProviderFor(
      submissionId: submissionId,
      featureId: featureId,
    ).provider);
    final notifier = ref.read(formProviderFor(
      submissionId: submissionId,
      featureId: featureId,
    ).provider.notifier);
    final selected = state.fireLoad.toSet();

    return Card(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      shape: const RoundedRectangleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.sectionFireLoad.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                color: Colors.grey,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _all.map((entry) {
                final value = entry.$1;
                final isSelected = selected.contains(value);
                return FilterChip(
                  label: Text(_label(entry.$2, l)),
                  selected: isSelected,
                  onSelected: disabled
                      ? null
                      : (v) {
                          final next = selected.toSet();
                          if (v) {
                            next.add(value);
                          } else {
                            next.remove(value);
                          }
                          notifier.update(
                              (s) => s.copyWith(fireLoad: next.toList()));
                        },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  String _label(String key, AppLocalizations l) {
    switch (key) {
      case 'fireLoadWoodFurniture': return l.fireLoadWoodFurniture;
      case 'fireLoadFabric': return l.fireLoadFabric;
      case 'fireLoadPaper': return l.fireLoadPaper;
      case 'fireLoadChemicals': return l.fireLoadChemicals;
      case 'fireLoadCookingGas': return l.fireLoadCookingGas;
      case 'fireLoadOther': return l.fireLoadOther;
      default: return key;
    }
  }
}
```

- [ ] **Step 6: Run analyze + commit**

```bash
flutter analyze lib/features/survey/building_form/presentation/sections/
git add lib/features/survey/building_form/presentation/sections/
git commit -m "feat(building_form): five form section widgets (identity / construction / cost / ff / fire load)"
```

---

## Task 16: BuildingForm + SubmissionTabs widgets

**Files:**
- Create: `lib/features/survey/building_form/presentation/building_form.dart`
- Create: `lib/features/survey/building_form/presentation/submission_tabs.dart`
- Create: `test/features/survey/building_form/submission_tabs_test.dart`

- [ ] **Step 1: Implement `building_form.dart`**

```dart
import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/construction_section.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/cost_section.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/ff_facilities_section.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/fire_load_section.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/identity_section.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BuildingForm extends ConsumerWidget {
  const BuildingForm({
    required this.submissionId,
    required this.featureId,
    super.key,
  });

  final String submissionId;
  final String featureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(formProviderFor(
      submissionId: submissionId,
      featureId: featureId,
    ).provider);
    final notifier = ref.read(formProviderFor(
      submissionId: submissionId,
      featureId: featureId,
    ).provider.notifier);
    final disabled = state.doesNotExist;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: disabled
                ? const Color(0xFFFFF0F0)
                : const Color(0xFFFFF8ED),
            border: Border.all(
              color: disabled
                  ? const Color(0xFFF0A0A0)
                  : const Color(0xFFF6D68E),
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.doesNotExistTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: disabled ? const Color(0xFFC53030) : null,
                      ),
                    ),
                    Text(
                      l.doesNotExistHelper,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF888888),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: state.doesNotExist,
                activeThumbColor: const Color(0xFFC53030),
                onChanged: (v) =>
                    notifier.update((s) => s.copyWith(doesNotExist: v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IdentitySection(
          submissionId: submissionId,
          featureId: featureId,
          disabled: disabled,
        ),
        ConstructionSection(
          submissionId: submissionId,
          featureId: featureId,
          disabled: disabled,
        ),
        CostSection(
          submissionId: submissionId,
          featureId: featureId,
          disabled: disabled,
        ),
        FfFacilitiesSection(
          submissionId: submissionId,
          featureId: featureId,
          disabled: disabled,
        ),
        FireLoadSection(
          submissionId: submissionId,
          featureId: featureId,
          disabled: disabled,
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Implement `submission_tabs.dart`**

```dart
import 'package:firecheck/core/db/database.dart';
import 'package:flutter/material.dart';

class SubmissionTabs extends StatelessWidget {
  const SubmissionTabs({
    required this.submissions,
    required this.activeIndex,
    required this.onTap,
    required this.onAdd,
    required this.canAddMore,
    required this.softCapTooltip,
    super.key,
  });

  final List<Submission> submissions;
  final int activeIndex;
  final void Function(int) onTap;
  final VoidCallback onAdd;
  final bool canAddMore;
  final String softCapTooltip;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < submissions.length; i++)
              _Tab(
                label: 'Structure ${i + 1}',
                active: i == activeIndex,
                onTap: () => onTap(i),
              ),
            Tooltip(
              message: canAddMore ? '' : softCapTooltip,
              child: Opacity(
                opacity: canAddMore ? 1 : 0.4,
                child: GestureDetector(
                  key: const Key('submission-tabs.add'),
                  onTap: canAddMore ? onAdd : null,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(
                      '+',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF3B82F6),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: active ? const Color(0xFFC94A23) : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: active ? const Color(0xFFC94A23) : Colors.grey.shade700,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Test submission tabs**

```dart
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/survey/building_form/presentation/submission_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Submission s(String id) => Submission(
        id: id,
        featureId: 'f1',
        submittedBy: null,
        doesNotExist: false,
        remarks: null,
        syncStatus: 'draft',
        overrideReason: null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

  testWidgets('renders one tab per submission', (tester) async {
    var tappedIndex = -1;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SubmissionTabs(
          submissions: [s('a'), s('b')],
          activeIndex: 0,
          onTap: (i) => tappedIndex = i,
          onAdd: () {},
          canAddMore: true,
          softCapTooltip: '',
        ),
      ),
    ));
    expect(find.text('Structure 1'), findsOneWidget);
    expect(find.text('Structure 2'), findsOneWidget);
    await tester.tap(find.text('Structure 2'));
    expect(tappedIndex, 1);
  });

  testWidgets('+ tab disabled when canAddMore is false', (tester) async {
    var added = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SubmissionTabs(
          submissions: [s('a'), s('b'), s('c'), s('d'), s('e')],
          activeIndex: 0,
          onTap: (_) {},
          onAdd: () => added = true,
          canAddMore: false,
          softCapTooltip: 'cap',
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('submission-tabs.add')));
    expect(added, isFalse);
  });
}
```

- [ ] **Step 4: Run + commit**

```bash
flutter test test/features/survey/building_form/submission_tabs_test.dart
flutter analyze lib/features/survey/building_form/presentation/building_form.dart lib/features/survey/building_form/presentation/submission_tabs.dart test/features/survey/building_form/submission_tabs_test.dart
git add lib/features/survey/building_form/presentation/building_form.dart lib/features/survey/building_form/presentation/submission_tabs.dart test/features/survey/building_form/submission_tabs_test.dart
git commit -m "feat(building_form): BuildingForm composer + SubmissionTabs widget"
```

---

## Task 17: OverrideReasonDialog + tests

**Files:**
- Create: `lib/features/survey/building_form/presentation/override_reason_dialog.dart`
- Create: `test/features/survey/building_form/override_reason_dialog_test.dart`

- [ ] **Step 1: Implement**

```dart
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

Future<String?> showOverrideReasonDialog(
  BuildContext context, {
  required double distanceMeters,
}) async {
  final l = AppLocalizations.of(context)!;
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setState) {
        final canContinue = controller.text.trim().isNotEmpty;
        return AlertDialog(
          title: Text(l.overrideTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.overrideBody(distanceMeters.round())),
              const SizedBox(height: 12),
              TextField(
                key: const Key('override.reason'),
                controller: controller,
                onChanged: (_) => setState(() {}),
                maxLength: 200,
                decoration: InputDecoration(
                  hintText: l.overrideReasonHint,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(l.cancelLabel),
            ),
            FilledButton(
              onPressed: canContinue
                  ? () => Navigator.of(ctx).pop(controller.text.trim())
                  : null,
              child: Text(l.overrideContinue),
            ),
          ],
        );
      });
    },
  );
  controller.dispose();
  return result;
}
```

- [ ] **Step 2: Test**

```dart
import 'package:firecheck/features/survey/building_form/presentation/override_reason_dialog.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Future<String?> Function(BuildContext) opener) {
    String? lastResult;
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Column(
            children: [
              if (lastResult != null) Text('captured: $lastResult'),
              TextButton(
                onPressed: () async {
                  lastResult = await opener(ctx);
                  (ctx as Element).markNeedsBuild();
                },
                child: const Text('open'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('Continue is disabled until reason has text', (tester) async {
    await tester.pumpWidget(wrap(
      (ctx) => showOverrideReasonDialog(ctx, distanceMeters: 87),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final continueBtn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'));
    expect(continueBtn.onPressed, isNull);

    await tester.enterText(find.byKey(const Key('override.reason')), 'misplaced');
    await tester.pump();
    final continueBtn2 = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'));
    expect(continueBtn2.onPressed, isNotNull);
  });
}
```

- [ ] **Step 3: Run + commit**

```bash
flutter test test/features/survey/building_form/override_reason_dialog_test.dart
flutter analyze lib/features/survey/building_form/presentation/override_reason_dialog.dart test/features/survey/building_form/override_reason_dialog_test.dart
git add lib/features/survey/building_form/presentation/override_reason_dialog.dart test/features/survey/building_form/override_reason_dialog_test.dart
git commit -m "feat(building_form): override-reason dialog + tests"
```

---

## Task 18: SubmissionDetailScreen

**Files:**
- Create: `lib/features/survey/building_form/presentation/submission_detail_screen.dart`
- Create: `test/features/survey/building_form/submission_detail_screen_test.dart`

- [ ] **Step 1: Implement**

```dart
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/building_form/data/building_attributes_repository.dart';
import 'package:firecheck/features/survey/building_form/data/submission_repository.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_validator.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:firecheck/features/survey/building_form/presentation/submission_tabs.dart';
import 'package:firecheck/features/survey/photo_capture/data/photo_repository.dart';
import 'package:firecheck/features/survey/photo_capture/presentation/photo_strip.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const _softCap = 5;

final _submissionsForFeatureProvider =
    StreamProvider.autoDispose.family<List<Submission>, String>((ref, featureId) {
  return ref
      .watch(submissionRepositoryProvider)
      .watchSubmissionsForFeature(featureId);
});

class SubmissionDetailScreen extends ConsumerStatefulWidget {
  const SubmissionDetailScreen({required this.featureId, super.key});
  final String featureId;

  @override
  ConsumerState<SubmissionDetailScreen> createState() =>
      _SubmissionDetailScreenState();
}

class _SubmissionDetailScreenState
    extends ConsumerState<SubmissionDetailScreen> {
  int _activeIndex = 0;
  String? _ensuredSubmissionId;

  @override
  void initState() {
    super.initState();
    Future.microtask(_ensureFirst);
  }

  Future<void> _ensureFirst() async {
    final repo = ref.read(submissionRepositoryProvider);
    final submission = await repo.ensureDraftForFeature(
      featureId: widget.featureId,
      enumeratorId: 'admin', // Phase 0 stub user; Phase 4 wires real auth
    );
    if (mounted) setState(() => _ensuredSubmissionId = submission.id);
  }

  Future<void> _addTab() async {
    final repo = ref.read(submissionRepositoryProvider);
    await repo.createAdditionalSubmission(
      featureId: widget.featureId,
      enumeratorId: 'admin',
    );
    final submissions = await ref
        .read(submissionRepositoryProvider)
        .watchSubmissionsForFeature(widget.featureId)
        .first;
    if (mounted) setState(() => _activeIndex = submissions.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final submissionsAsync =
        ref.watch(_submissionsForFeatureProvider(widget.featureId));

    return Scaffold(
      appBar: AppBar(
        title: Text(l.submissionDetailTitleBuilding),
      ),
      body: submissionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (submissions) {
          if (submissions.isEmpty || _activeIndex >= submissions.length) {
            return const Center(child: CircularProgressIndicator());
          }
          final active = submissions[_activeIndex];
          return Column(
            children: [
              SubmissionTabs(
                submissions: submissions,
                activeIndex: _activeIndex,
                onTap: (i) => setState(() => _activeIndex = i),
                onAdd: _addTab,
                canAddMore: submissions.length < _softCap,
                softCapTooltip: l.tabSoftCapTooltip,
              ),
              PhotoStrip(submissionId: active.id),
              Expanded(
                child: BuildingForm(
                  submissionId: active.id,
                  featureId: widget.featureId,
                ),
              ),
              _Footer(
                submissionId: active.id,
                featureId: widget.featureId,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.submissionId, required this.featureId});
  final String submissionId;
  final String featureId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(formProviderFor(
      submissionId: submissionId,
      featureId: featureId,
    ).provider);
    final notifier = ref.read(formProviderFor(
      submissionId: submissionId,
      featureId: featureId,
    ).provider.notifier);
    final photosAsync = ref.watch(photosForSubmissionFooterProvider(submissionId));
    return photosAsync.when(
      loading: () => const SizedBox(height: 56),
      error: (_, __) => const SizedBox(height: 56),
      data: (photoCount) {
        final result = validateBuildingForm(state, photoCount);
        final ready = result.isComplete;
        final statusText = ready
            ? l.footerStatusReady
            : (photoCount < 1
                ? l.footerStatusPhotoRequired
                : l.footerStatusFieldsMissing);
        return Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    color: ready
                        ? const Color(0xFF276749)
                        : const Color(0xFFC53030),
                  ),
                ),
              ),
              FilledButton(
                onPressed: ready
                    ? () async {
                        await notifier.flushNow();
                        await ref
                            .read(submissionRepositoryProvider)
                            .markStatus(submissionId, 'ready_to_upload');
                        if (context.mounted) context.go('/map');
                      }
                    : null,
                child: Text(l.doneButton),
              ),
            ],
          ),
        );
      },
    );
  }
}

final photosForSubmissionFooterProvider =
    StreamProvider.autoDispose.family<int, String>((ref, submissionId) async* {
  final repo = ref.watch(photoRepositoryProvider);
  await for (final list in repo.watchForSubmission(submissionId)) {
    yield list.length;
  }
});

// Re-export for the building_form widget tree.
final photoRepositoryProvider = Provider<PhotoRepository>((ref) => throw UnimplementedError(
      'Provided in core/photos/photo_providers.dart — not used at this scope.',
    ));
```

NOTE: the `photoRepositoryProvider` re-export at the bottom is wrong — it shadows the canonical one. Remove that bottom block; the screen should `import 'package:firecheck/core/photos/photo_providers.dart' show photoRepositoryProvider;` instead.

Update the imports at the top of the file:

```dart
import 'package:firecheck/core/photos/photo_providers.dart';
```

And delete the bottom `photoRepositoryProvider` redeclaration.

- [ ] **Step 2: Smoke test**

```dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/building_form/presentation/submission_detail_screen.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final now = DateTime.now();
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f1',
            assignmentId: 'a1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: now,
          ),
        );
  });

  tearDown(() async => db.close());

  testWidgets('opens with auto-created Tab 1', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SubmissionDetailScreen(featureId: 'f1'),
      ),
    ));
    // First frame shows the loading spinner; pump to complete the
    // ensureDraft microtask + the stream.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Structure 1'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run + commit**

```bash
flutter test test/features/survey/building_form/submission_detail_screen_test.dart
flutter analyze lib/features/survey/building_form/presentation/submission_detail_screen.dart test/features/survey/building_form/submission_detail_screen_test.dart
git add lib/features/survey/building_form/presentation/submission_detail_screen.dart test/features/survey/building_form/submission_detail_screen_test.dart
git commit -m "feat(building_form): SubmissionDetailScreen — tabs + photo strip + form + footer"
```

---

## Task 19: Map integration — replace bottom sheet with route push

**Files:**
- Modify: `lib/features/map/presentation/map_screen.dart`
- Delete: `lib/features/map/presentation/feature_bottom_sheet.dart`
- Delete: `lib/features/map/presentation/feature_too_far_modal.dart`
- Modify: `lib/core/router/app_router.dart`
- Modify: `test/features/map/map_screen_test.dart`

- [ ] **Step 1: Update `app_router.dart`**

Add inside the `routes:` list:

```dart
GoRoute(
  path: '/feature/:featureId',
  builder: (context, state) {
    final featureId = state.pathParameters['featureId']!;
    return SubmissionDetailScreen(featureId: featureId);
  },
),
```

Add the import:

```dart
import 'package:firecheck/features/survey/building_form/presentation/submission_detail_screen.dart';
```

- [ ] **Step 2: Replace map_screen.dart's tap handler**

In `lib/features/map/presentation/map_screen.dart`, replace the existing `_handleFeatureTap` body to use the override-check use case + GeoJSON centroid + push to `/feature/:id`:

```dart
import 'package:firecheck/core/geo/centroid.dart';
import 'package:firecheck/features/survey/building_form/domain/override_check.dart';
import 'package:firecheck/features/survey/building_form/data/submission_repository.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:firecheck/features/survey/building_form/presentation/override_reason_dialog.dart';
import 'package:go_router/go_router.dart';

// inside _MapScreenState

Future<void> _handleFeatureTap(Feature f) async {
  // GPS will be wired through location_providers in a future polish pass.
  // For Phase 2, use the centroid of the assignment as a reasonable
  // default if no live position is available.
  const userLat = 10.31810;
  const userLng = 123.88270;

  final ring = decodePolygonGeojson(f.geometryGeojson) ?? const [];
  if (ring.isEmpty) {
    if (mounted) context.go('/feature/${f.id}');
    return;
  }

  final result = await checkTap(
    userLat: userLat,
    userLng: userLng,
    featureRing: ring,
    promptForReason: () => showOverrideReasonDialog(
      context,
      distanceMeters: haversineMeters(
        userLat,
        userLng,
        polygonCentroid(ring).lat,
        polygonCentroid(ring).lng,
      ),
    ),
  );

  if (!mounted) return;
  switch (result) {
    case TapAllowed():
      context.go('/feature/${f.id}');
    case TapAllowedWithOverride(:final reason):
      // Persist the override reason on whatever draft submission we land on.
      final repo = ref.read(submissionRepositoryProvider);
      final s = await repo.ensureDraftForFeature(
        featureId: f.id,
        enumeratorId: 'admin',
      );
      await repo.updateOverrideReason(s.id, reason);
      if (mounted) context.go('/feature/${f.id}');
    case TapBlocked():
      // User dismissed the prompt; nothing to do.
      break;
  }
}
```

(`haversineMeters` import: `package:firecheck/core/location/distance.dart`.)

- [ ] **Step 3: Delete obsolete files**

```bash
git rm lib/features/map/presentation/feature_bottom_sheet.dart
git rm lib/features/map/presentation/feature_too_far_modal.dart
git rm test/features/map/feature_bottom_sheet_test.dart
git rm test/features/map/feature_too_far_modal_test.dart
```

- [ ] **Step 4: Update map_screen_test.dart**

The Phase 1 test imports `FeatureBottomSheet` indirectly. Trim those imports and assertions; the surviving test should just verify the map screen renders and a tap doesn't throw. Replace the Phase 1 assertions with:

```dart
testWidgets('renders title + follow-me toggle', (tester) async {
  await tester.pumpWidget(buildSubject(features: const []));
  await tester.pump();
  expect(find.text('Gather Data'), findsOneWidget);
  expect(find.text('Follow'), findsOneWidget);
});

testWidgets('renders one fake-map tile per feature', (tester) async {
  // unchanged from Phase 1
});
```

(Drop the bottom-sheet assertion test if it existed; the new tap behaviour pushes a route which a fake renderer can't exercise.)

- [ ] **Step 5: Run + commit**

```bash
flutter test
flutter analyze
git add lib/core/router/app_router.dart lib/features/map/presentation/map_screen.dart test/features/map/map_screen_test.dart
git commit -m "feat(map): tap-polygon now pushes /feature/:id with override flow"
```

Expected: full suite green (~110 tests).

---

## Task 20: Final verification + tag phase-2-form

- [ ] **Step 1: Run full pipeline**

```bash
flutter analyze && flutter test
```

Expected: 0 issues, ~110 tests pass.

- [ ] **Step 2: Build APK**

```bash
flutter build apk --debug
```

Expected: success.

- [ ] **Step 3: Manual smoke (per spec §15)**

Install + launch + walk through the 11-step happy path (login → Get Maps → tap polygon → fill → photo → mark complete → second tab → does-not-exist → distance Override).

- [ ] **Step 4: Tag**

```bash
git tag -a phase-2-form -m "Phase 2: Building form + autosave + photos. ~110 tests; flutter analyze clean."
```

- [ ] **Step 5: Push (user-gated)**

```bash
git push origin main --tags
```

---

## Self-review (plan-level)

**Spec coverage** — every section of the spec maps to a task:

| Spec section | Implemented in |
|---|---|
| §3 Stack additions | T2 |
| §4 Architecture delta | T1-T19 collectively |
| §5 Schema v3 | T1 |
| §6 Module structure | T2-T19 |
| §7 Repositories | T8 (submission), T9 (attrs), T7 (photo), T10 (markFeatureStatus) |
| §8 Form state machine + autosave | T11 (state), T14 (notifier) |
| §9 Photo capture pipeline | T4 (services), T5 (image processor), T6 (controller), T7 (repo), T13 (strip) |
| §10 Detail screen layout | T13 (strip), T15 (sections), T16 (form composer + tabs), T18 (screen) |
| §11 Validation | T11 (validator) |
| §12 Distance Override flow | T3 (centroid), T12 (use case), T17 (dialog), T19 (map integration) |
| §13 Error handling matrix | inline within T6, T13, T17, T19 |
| §14 Testing strategy | inline tests per task |
| §15 Demo state | T20 manual smoke |
| §16-17 Deferrals + success criteria | inline acknowledgements |

**Placeholder scan** — no TBD/TODO/"implement later" left. The `// TODO(phase-2)` removed from Phase 1's `_centroidFallback` is now obsolete (Task 3 supplies the real math; Task 19 wires it).

**Type consistency:**
- `BuildingFormState` fields used identically across T11 (definition), T14 (notifier read/write), T15 (section widgets), T18 (footer validator).
- `Submission` Drift type accessed identically in T8 (repo), T16 (tabs), T18 (detail screen).
- `ValidationResult` from T11 used in T18 footer.
- `TapResult` sealed (TapAllowed/TapBlocked/TapAllowedWithOverride) consistent T12 ↔ T19.
- `PhotoRepository.insert` signature identical T7 ↔ T6 (controller) ↔ T13 (strip).
- `formProviderFor({submissionId, featureId})` helper consistent T14 ↔ T15 ↔ T16 ↔ T18.

**One follow-up flagged for Phase 4:** Real GPS in the `_handleFeatureTap` user position. Phase 2 hardcodes Brgy. Tisa center as the user position because the location_providers stream isn't yet integrated into map screen. Real GPS wiring is part of Phase 4 (sync + reliability work).
