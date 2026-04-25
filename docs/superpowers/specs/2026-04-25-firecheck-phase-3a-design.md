# FireCheck Mobile — Phase 3a Design Spec

**Date:** 2026-04-25
**Status:** Draft v1 (brainstorming output)
**Phase:** 3a — Roads form + Add-new-feature long-press
**Parent spec:** `docs/superpowers/specs/2026-04-24-firecheck-mobile-design.md`
**Predecessor:** `docs/superpowers/specs/2026-04-24-firecheck-phase-2-design.md`
**Successor (planned):** `docs/superpowers/specs/<date>-firecheck-phase-3b-design.md` (OLP household survey)

## 1. Summary

Phase 3a adds the roads attribution form and the in-field "add new feature" capability to FireCheck Mobile. After this ships, an enumerator can:

1. Tap a road polyline on the map → distance check → road detail screen with the same UX skeleton as the building form (tabs, photo strip, autosave, override flow, Done).
2. Toggle "+ New Feature" on the map → long-press a location → pick Building or Road → form opens with a Point geometry pre-filled, the new feature is marked `is_new=true` and renders as a blue pin until completed.

**OLP household survey is intentionally deferred to Phase 3b** — that submodule depends on the BFP CFPP rubric (now in hand from the user-supplied OLP PRD) and ships in its own spec + plan cycle.

## 2. Scope

### In scope

- **Roads form**: `road_attributes` repository + `RoadFormState` + validator + `RoadFormNotifier` (debounced autosave) + composer + 3 section widgets.
- **Detail screen unification**: `SubmissionDetailScreen` becomes feature-type-aware, branches body to render `BuildingForm` or `RoadForm`. Tabs / photo strip / footer / Done button stay shared.
- **Polyline tap flow**: tapping a road polyline routes through the same GPS + 50 m distance check + override dialog flow established in Phase 2 T19. New `polylineMidpoint` helper for centroid calculation.
- **Add-new-feature long-press**:
  - Map's "+ New Feature" pill becomes interactive (currently a disabled placeholder).
  - **Single-shot toggle** (per Q5): tap pill → enters add mode → first long-press creates a feature → toggle auto-exits.
  - Long-press → drops Point GeoJSON → bottom sheet "Building or Road?" → on pick, creates feature row + draft submission and routes to detail screen.
  - Boundary check: long-press outside the assignment polygon shows a snackbar and is dropped.
- **Blue-pin rendering**: features with `is_new=true` render as a blue point annotation; polygon/polyline layers skip them.

### Out of scope

- OLP household survey (Phase 3b).
- Sync queue, Supabase upload, photo upload to Storage (Phase 4).
- Polygon / road reshape (master spec §15 documented limitation).
- Multi-vertex LineString or Polygon capture for new features. Single Point only; supervisor refines server-side.
- Long-press-to-delete an orphan blue pin. Deletion goes through the form's does-not-exist toggle.
- Add-mode keyboard / accessibility shortcuts. Voice-over labels yes; keyboard nav deferred to Phase 5 polish.
- Multi-feature batch add (single-shot toggle by design — see decision Q5).

## 3. Architecture

### 3.1 Module layout

```
lib/
├── core/
│   └── geo/
│       ├── centroid.dart              # existing (P2)
│       ├── polyline_midpoint.dart     # NEW: midpoint of a LineString
│       └── point_in_polygon.dart      # NEW: ray-casting inside test
├── features/
│   ├── map/
│   │   └── presentation/
│   │       ├── map_screen.dart        # MODIFIED: add-mode toggle, long-press
│   │       └── map_renderer.dart      # MODIFIED: onLongPress, is_new pin layer
│   ├── new_feature/                   # NEW MODULE
│   │   ├── data/
│   │   │   └── new_feature_repository.dart
│   │   └── presentation/
│   │       └── feature_type_picker.dart  # bottom sheet
│   └── survey/
│       ├── building_form/             # existing (P2)
│       │   └── presentation/
│       │       └── submission_detail_screen.dart  # MODIFIED: type-aware
│       └── road_form/                 # NEW MODULE
│           ├── data/
│           │   └── road_attributes_repository.dart
│           ├── domain/
│           │   ├── road_form_state.dart
│           │   └── road_form_validator.dart
│           └── presentation/
│               ├── road_form.dart
│               ├── road_form_notifier.dart
│               ├── road_form_providers.dart
│               └── sections/
│                   ├── _road_identity_section.dart
│                   ├── _road_dimensions_section.dart
│                   └── _road_features_section.dart
```

Shared widgets from Phase 2 reused as-is: `_section_card.dart`, `_persistent_text_field.dart`, `submission_tabs.dart`, `photo_strip.dart`, `override_reason_dialog.dart`.

### 3.2 Data flow

**Tap-polyline (existing road feature):**
```
MapScreen._handleFeatureTap(road)
  → resolvePosition (warm GPS, await with spinner)
  → decodePolylineGeojson(geometryGeojson)
  → polylineMidpoint(coords) → LatLng
  → haversineMeters(user, midpoint)
  → if > 50m: showOverrideReasonDialog → reason
  → ensureDraftForFeature(featureId, enumeratorId)
  → if reason: updateOverrideReason(submission.id, reason)
  → context.go('/feature/$featureId')
  → SubmissionDetailScreen reads feature.featureType
  → renders RoadForm
```

**Long-press (add new feature):**
```
MapScreen._handleLongPress(lat, lng)
  → if !_addModeActive: ignore
  → pointInPolygon(lat, lng, assignment.boundaryPolygonGeojson)
  → if outside: snackbar("outside boundary") + return
  → showModalBottomSheet(FeatureTypePicker) → 'building' | 'road' | null
  → if null: setState(_addModeActive = false) + return
  → newFeatureRepo.createNewFeature(assignmentId, type, lat, lng) → Feature
  → submissionRepo.ensureDraftForFeature(feature.id, enumeratorId)
  → setState(_addModeActive = false)         // single-shot exit
  → context.go('/feature/${feature.id}')
```

### 3.3 State machines

No new sealed-class state machines are introduced in Phase 3a. The single piece of state added is the `bool _addModeActive` flag in `_MapScreenState`, which is appropriate to keep as widget state (no testable transitions worth modeling separately).

## 4. Schema impact

**Drift schema bump: NONE.** Schema stays at v3.

| Table | Status | Phase 3a use |
|---|---|---|
| `features` | exists | New rows inserted with `is_new=true` for add-new flow. |
| `submissions` | exists | Reuses Phase 2 lifecycle. |
| `road_attributes` | **exists from Phase 0** | First wired this phase. Schema verified (`is_bridge`, `road_name`, `width_meters`, `road_features_json`, `others_description`). |
| `photos` | exists | Reused unchanged. |

No new migrations. No `sync_jobs` writes (Phase 4 territory).

## 5. Repositories

### 5.1 New repositories

**`RoadAttributesRepository`** (`lib/features/survey/road_form/data/`)
```dart
Future<void> upsertForSubmission(String submissionId, RoadAttributesCompanion attrs);
Future<RoadAttribute?> findBySubmission(String submissionId);
static List<String> decodeStringList(String json);  // JSON ↔ List<String>
```

**`NewFeatureRepository`** (`lib/features/new_feature/data/`)
```dart
Future<Feature> createNewFeature({
  required String assignmentId,
  required String featureType, // 'building' | 'road'
  required double lat,
  required double lng,
});
```
Inserts a `features` row with:
- `id` = uuid v4
- `featureType` = passed type
- `geometryGeojson` = `{"type":"Point","coordinates":[lng,lat]}`
- `isNew` = **true**
- `status` = `'unfilled'`
- `createdAt` = now

Implementation uses `into(features).insertReturning(...)` so the inserted row is returned in one round-trip.

### 5.2 Modified repositories

**`FeatureRepository`** — no signature changes. `markFeatureStatus` already handles new features correctly (a feature with no submissions → `unfilled`, regardless of `isNew`).

## 6. Validation rules

### 6.1 Road form validator

Pure function: `validateRoadForm(RoadFormState state, int photoCount) → ValidationResult`.

**Field errors (blockers):**

| Field | Rule |
|---|---|
| `widthMeters` | Required, must be > 0 |
| `photo` | `photoCount >= 1` |
| `othersDescription` | Required if `roadFeatures.contains('others')` |

**Warnings (non-blocking):**

| Field | Rule |
|---|---|
| `roadName` | Empty roadName |
| `widthMeters` | Width > 30 m (probable typo) |

**Does-not-exist short-circuit:** when `state.doesNotExist == true`, all blockers waived **except** photo. Matches `BuildingFormValidator` behavior.

### 6.2 Boundary check (add-new)

`pointInPolygon(lat, lng, boundaryGeojson) → bool` — pure ray-casting algorithm. Long-press handler in MapScreen rejects taps where this returns false; user sees `l.outsideBoundarySnackbar`.

## 7. UI specifications

### 7.1 Road detail screen (via unified `SubmissionDetailScreen`)

Same skeleton as Phase 2 building screen:
- AppBar title: `l.submissionDetailTitleRoad` ("Road")
- `SubmissionTabs` (multi-submission tabs, soft cap 5)
- `PhotoStrip` (≥1 required)
- `RoadForm` (3 sections + does-not-exist switch)
- Footer: status text + Done button (validation-driven)

### 7.2 Road form sections

**_RoadIdentitySection:**
- `road_name` text input (`PersistentTextField`)
- `is_bridge` switch (defaults off)

**_RoadDimensionsSection:**
- `width_meters` numeric input (`PersistentTextField` with `keyboardType: numberWithOptions(decimal: true)`, helperText shows ">30 m looks unusual" when triggered)

**_RoadFeaturesSection:**
- 4 checkboxes: `vendor`, `pedestrian`, `parking`, `others`
- When `others` is checked, conditional `others_description` text input appears below

### 7.3 Map add-mode UX

**"+ New Feature" pill:**
- Idle: light grey background, white text "+ New Feature"
- Active: solid blue background `0xFF3B82F6`, white text "Tap & hold to drop pin"

**Top banner (active only):**
- Material banner above the map: "Long-press the map to add a building or road here. Tap the pill again to cancel."
- Dismissed automatically on first long-press, on cancel, or after feature creation.

**Bottom sheet (`FeatureTypePicker`):**
- Slides up after long-press completes the boundary check.
- Two large `FilledButton.tonal`:
  - **Building** (Material icon `domain`)
  - **Road** (Material icon `route`)
- Cancel TextButton at bottom.

**Blue-pin rendering** (Mapbox layer):
- `PointAnnotationManager` for `is_new=true` features.
- Color: `0xFF3B82F6` fill, white stroke (2 px).
- Polygon / polyline layers skip features where `isNew == true` so a feature isn't double-rendered.

## 8. i18n additions

~15 new ARB keys in both `lib/core/i18n/app_en.arb` and `lib/core/i18n/app_tl.arb`:

| Key | EN | TL |
|---|---|---|
| `submissionDetailTitleRoad` | Road | Kalye |
| `sectionRoadIdentity` | Road identity | Pagkakakilanlan ng kalye |
| `sectionRoadDimensions` | Dimensions | Sukat |
| `sectionRoadFeatures` | Features | Mga katangian |
| `fieldRoadName` | Road name | Pangalan ng kalye |
| `fieldIsBridge` | This is a bridge | Tulay ito |
| `fieldWidthMeters` | Width (m) | Lapad (m) |
| `widthMetersUnusual` | Width over 30 m looks unusual | Mukhang malayo masyado ang lapad |
| `roadFeatureVendor` | Vendor stalls | Mga tindahan |
| `roadFeaturePedestrian` | Pedestrian | Para sa naglalakad |
| `roadFeatureParking` | Parking | Paradahan |
| `roadFeatureOthers` | Others | Iba pa |
| `roadFeatureOthersDescription` | Describe other features | Ilarawan ang iba pang katangian |
| `addModeBannerHint` | Long-press the map to add a building or road. Tap the pill again to cancel. | Pindutin nang matagal ang mapa upang magdagdag ng gusali o kalye. Pindutin muli ang pill para kanselahin. |
| `outsideBoundarySnackbar` | Long-press is outside your assignment area | Wala sa loob ng iyong nasasakupang lugar |
| `pickFeatureTypeTitle` | What did you find? | Anong nakita mo? |
| `pickFeatureTypeBuilding` | Building | Gusali |
| `pickFeatureTypeRoad` | Road | Kalye |

Generated files: `flutter gen-l10n` after each ARB change.

## 9. Testing strategy

### 9.1 Unit tests (no Flutter deps)

- `polylineMidpoint` — known LineString → known midpoint, 2-vertex degenerate, multi-segment averaged correctly
- `pointInPolygon` — point inside test ring, on a vertex, on an edge, outside (Brgy. Tisa rectangle reused from `override_check_test`)
- `RoadFormState.copyWith` + clear-flags
- `validateRoadForm` — empty form blockers, width=0 blocker, "others" without description blocker, doesNotExist short-circuit, width=35 warning, happy path

### 9.2 Repository tests (NativeDatabase.memory + FK chain seed)

- `RoadAttributesRepository.upsert` round-trips JSON-encoded `roadFeatures` list
- `NewFeatureRepository.createNewFeature` inserts with `isNew=true`, status `'unfilled'`, well-formed Point GeoJSON

### 9.3 Notifier tests

- `RoadFormNotifier.update` debounces 500ms then writes
- `flushNow()` writes immediately
- does-not-exist toggle flips submissions row + skips road_attributes write

### 9.4 Widget tests

- `RoadForm` composer renders 3 sections, sections disable when `doesNotExist=true`
- `_RoadFeaturesSection` shows `othersDescription` field only when "others" is checked
- `FeatureTypePicker` bottom sheet renders both type buttons; tapping returns the right type
- `MapScreen` — tapping the "+ New Feature" pill toggles add-mode visual state
- `SubmissionDetailScreen` smoke test renders `RoadForm` for a road feature (deferred per Phase 2 T18 precedent if `flutter_tester` hangs)

### 9.5 Integration

End-to-end create-new-road via `FakeMapRenderer.simulateLongPress(lat, lng)` → expect form opens + feature row exists with `isNew=true`.

### 9.6 Acceptance gate

- `flutter analyze` → No issues found
- `flutter test` ≥ 130 tests passing (Phase 2 ended at 115; Phase 3a adds ~15-20)
- `flutter build apk --debug` → succeeds
- Manual happy path on Pixel 7 emulator:
  - Tap road polyline → form
  - Long-press in add mode → type picker → form opens with new feature
  - New feature appears as blue pin until completed
- Tag `phase-3a-roads-and-add-new` (push remains user-gated per established convention)

## 10. Conventions reused from Phase 0–2

- Drift code generation via `dart run build_runner build --delete-conflicting-outputs`
- Riverpod 2.5 with `StateNotifierProvider.autoDispose.family`
- `value class with copyWith + clear-flags` for form state
- `very_good_analysis` lint set (project-wide overrides preserved)
- `subagent-driven-development` for plan execution (one subagent per task, two-stage review)
- Commit message format: `<type>(<scope>): <subject>` — types follow Phase 2 convention
- Co-Authored-By: Claude trailer on every commit
- No automatic push; tagging happens at the final task; user pushes manually

## 11. Open items deferred to Phase 3b

These Phase 3b risks are noted now but addressed only when Phase 3b's spec is written:

- BFP CFPP rubric Section B item count discrepancy (PRD §4 vs §6: total = 35 vs "30 total across B–E")
- BFP CFPP rubric 12/23 boundary verification (PRD §4 calls out)
- Section A material multi-select vs strict-one (PRD §11 open question)
- Real BFP-vetted Tagalog suggestion strings vs draft phrasings (PRD §11)
