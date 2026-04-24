# FireCheck Mobile — Phase 2 Design Spec

**Date:** 2026-04-24
**Status:** Draft v1 (brainstorming output)
**Phase:** 2 — Building form + autosave + photo capture
**Parent spec:** `docs/superpowers/specs/2026-04-24-firecheck-mobile-design.md`
**Predecessor:** `docs/superpowers/specs/2026-04-24-firecheck-phase-1-design.md`

## 1. Summary

Phase 2 turns FireCheck from a map viewer into a real data-collection tool. Tapping a polygon on the map no longer opens a placeholder bottom sheet — it pushes a full **SubmissionDetailScreen** with horizontally-scrollable tabs (multi-submission), a photo capture strip, and a long-scroll building attribution form whose fields autosave to Drift 500 ms after every edit. The form covers all RA 9514 building attribution fields per the parent spec. Real GeoJSON centroid math drives the 50 m distance check; an Override flow records a free-text reason for supervisor review. The "does not exist" toggle short-circuits the form while still requiring at least one photo.

No upload yet; that's Phase 4. No road form, no OLP household survey, no add-new-feature long-press; those are Phase 3.

## 2. Goals & Non-Goals

### Goals
1. Schema v3 migration adding `submissions.override_reason` (FK pragma + indexes from Phases 1-2 already enforced via `beforeOpen`).
2. Detail screen replaces Phase 1's placeholder bottom sheet.
3. Multi-submission tabs (auto-create first on polygon tap; "+" tab creates new; soft cap of 5; horizontal scroll if many).
4. Building attribution form with autosaved fields per the parent spec's `BuildingAttributes` shape (CBMS ID, name, RA 9514 type, storeys, material, cost as exact-or-range, fire-fighting facilities multi-select, fire load multi-select).
5. Photo capture: system camera → resize to 1600 px longest edge → JPEG 85% → preserve EXIF GPS → save to local app dir → reactive thumbnail strip.
6. Required-photo enforcement (≥1 per submission, including does-not-exist submissions).
7. Real haversine distance check using actual GeoJSON polygon centroids (Phase 1 hardcoded these).
8. Override flow: distance > 50 m → reason-required modal → reason persisted on `submissions.override_reason`.
9. Does-not-exist toggle short-circuits validation but still requires a photo.
10. Map polygon color-coding (red/yellow/green) updates reactively as the user fills the form.

### Non-Goals
- Road attribution form (Phase 3).
- OLP household survey (Phase 3).
- Add new feature via long-press (Phase 3).
- Sync queue / upload to Supabase (Phase 4).
- Background photo upload (Phase 4).
- Pre-submit review screen (Phase 4).
- Camera in-app preview / overlays (use system camera; advanced UI is Phase 5 polish).
- iOS support (Phase 1 of v2).
- Logout button anywhere (Phase 5 polish).

## 3. Stack additions

| Dep | Why |
|---|---|
| `image_picker` | System camera capture; permission handling |
| `image` | Pure-Dart resize / JPEG re-encode |
| `native_exif` | Read + write EXIF GPS tags across the resize |

`image_picker` requires an Android `CAMERA` permission in `AndroidManifest.xml`.

## 4. Architecture delta

Builds on Phases 0+1's layered architecture. New cross-cutting infrastructure under `core/`:

- `core/photos/` — `CameraService`, `ImageProcessor`, `PhotoStorageService` + Riverpod providers.
- `core/geo/centroid.dart` — pure GeoJSON polygon centroid math (Phase 1 stubbed it).

Two new feature modules under `features/survey/`:

- `features/survey/photo_capture/` — `PhotoRepository` + `PhotoStrip` widget + `PhotoPreviewScreen`. Phase 3's road form will reuse this module.
- `features/survey/building_form/` — the heaviest module to date. Detail screen, tab strip, all form section widgets, the `BuildingFormNotifier` (debounced autosave), validators, override-reason dialog.

Phase 1's bottom sheet (`feature_bottom_sheet.dart`) and the `showModalBottomSheet` call in `map_screen.dart` are deleted. The map's polygon tap handler navigates to `/feature/:featureId` instead.

The Phase 1 invariant holds: every write hits Drift first; the UI reads via reactive streams. Phase 2 just adds new write paths and a new consumer screen.

## 5. Schema v3

Single column added.

**Migration** (`MigrationStrategy.onUpgrade`):

```dart
if (from < 3) {
  await m.addColumn(submissions, submissions.overrideReason);
}
```

**Drift table change** (`lib/core/db/tables/submissions.dart`):

```dart
TextColumn get overrideReason => text().nullable()();
```

**Server-side** (`supabase/migrations/003_override_reason.sql`):

```sql
alter table public.submissions add column override_reason text;
```

PostgREST exposes the new column automatically — no computed-column tricks needed (it's plain text).

**Test** (`test/core/db/migration_v2_to_v3_test.dart`): asserts `override_reason` column exists post-upgrade, FK pragma still on, indexes still present, schema version is 3.

Lands as Phase 2's Task 1 (strict prerequisite).

## 6. Module structure (Phase 2 additions + modifications)

```
pubspec.yaml                                      Modify — add image_picker, image, native_exif
android/app/src/main/AndroidManifest.xml          Modify — CAMERA permission

supabase/migrations/
  003_override_reason.sql                         New — adds submissions.override_reason

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
        domain/
          captured_photo.dart                     New — value type with path + GPS
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
          ra_9514_fallback.dart                   New — hardcoded fallback list (10 occupancy groups)
          required_fields.dart                    New — pure "is this complete" predicate
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
        feature_repository.dart                   Modify — add markFeatureStatus(featureId)
      presentation/
        map_screen.dart                           Modify — replace bottom sheet with route push
        feature_bottom_sheet.dart                 Delete — replaced by detail screen
        feature_too_far_modal.dart                Modify — adapted into override flow

test/
  core/
    db/
      migration_v2_to_v3_test.dart                New
    photos/
      image_processor_test.dart                   New — resize + EXIF (fixture image)
      camera_service_test.dart                    New — fake camera flow
      photo_capture_controller_test.dart          New
    geo/
      centroid_test.dart                          New — known-answer centroids
  features/
    survey/
      photo_capture/
        photo_repository_test.dart                New
        photo_strip_test.dart                     New — widget test
      building_form/
        submission_repository_test.dart           New — multi-submission, soft cap
        building_attributes_repository_test.dart  New
        building_form_validator_test.dart         New — required-field rules
        building_form_notifier_test.dart          New — debounced autosave
        sections/                                 New — widget tests per section
        building_form_test.dart                   New — full form widget test
        submission_detail_screen_test.dart        New — tabs + tab switching
        override_reason_dialog_test.dart          New
```

**Boundaries:**
- `core/photos/` is the **infrastructure** layer (file system + image lib). `features/survey/photo_capture/` is the **feature** layer (UI strip + Drift CRUD).
- `core/geo/centroid.dart` is **pure** Dart — no Flutter, no async. Tested standalone.
- Form sections are split into individual files (~80–150 lines each) to keep `building_form.dart` under control.
- `building_form_validator.dart` and `required_fields.dart` are **pure functions** that take a `BuildingFormState` and return validation results.

## 7. Repositories

**`SubmissionRepository`** — owner of `submissions` rows.

```dart
Future<Submission> ensureDraftForFeature(String featureId, String enumeratorId);
  // Idempotent. If no draft exists for this feature, creates one. Returns Tab 1.

Future<Submission> createAdditionalSubmission(String featureId, String enumeratorId);
  // Always creates a NEW draft. Used by the "+" tab.

Stream<List<Submission>> watchSubmissionsForFeature(String featureId);
  // Drives the tab strip — emits submissions ordered by created_at ASC.

Future<int> countSubmissionsForFeature(String featureId);
  // Used to enforce the soft cap of 5.

Future<void> updateOverrideReason(String submissionId, String reason);

Future<void> updateDoesNotExist(String submissionId, bool doesNotExist);

Future<void> markStatus(String submissionId, String syncStatus);
  // 'draft' | 'in_progress' | 'ready_to_upload'

Future<void> deleteSubmission(String submissionId);
  // Cascades to building_attributes + photos via Drift FK.
```

**`BuildingAttributesRepository`** — one row per submission_id.

```dart
Stream<BuildingAttribute?> watchForSubmission(String submissionId);
Future<void> upsertForSubmission({ ... all attribute fields ... });
```

**`PhotoRepository`** — Drift CRUD + on-disk file lifecycle.

```dart
Stream<List<Photo>> watchForSubmission(String submissionId);
Future<int> countForSubmission(String submissionId);
Future<void> insert({
  required String submissionId,
  required String localPath,
  required DateTime capturedAt,
  double? gpsLat,
  double? gpsLng,
});
Future<void> delete(String photoId);   // unlinks the file too
```

**Extended `FeatureRepository`** (Phase 1) — adds:

```dart
Future<void> markFeatureStatus(String featureId);
  // Recomputes feature.status from its submissions:
  //   any submission complete → 'complete'
  //   any in_progress         → 'in_progress'
  //   else                    → 'unfilled'
  // Called from BuildingFormNotifier after every debounced save so the
  // map's color-coding updates reactively.
```

**Multi-submission tab order:** `created_at ASC`. New tabs append right.

**Soft cap of 5:** `SubmissionDetailScreen` watches `countSubmissionsForFeature`. The "+" tab disables itself with a tooltip beyond 5. User can delete a tab to free a slot.

## 8. Form state machine + autosave

The trickiest piece. One Riverpod `StateNotifier` per submission, lifetime = `SubmissionDetailScreen` open on that tab.

### State shape

`BuildingFormState` is a value type (`copyWith`-able) holding all form fields plus `submissionId`, `doesNotExist`, `overrideReason`.

### `BuildingFormNotifier`

```dart
class BuildingFormNotifier extends StateNotifier<BuildingFormState> {
  Timer? _debounce;
  static const _debounceWindow = Duration(milliseconds: 500);

  void update(BuildingFormState Function(BuildingFormState) mutate) {
    state = mutate(state);
    _debounce?.cancel();
    _debounce = Timer(_debounceWindow, _flush);
  }

  Future<void> _flush() async {
    await attrsRepo.upsertForSubmission(submissionId: ..., /* all fields */);
    if (state.doesNotExist) {
      await submissionRepo.updateDoesNotExist(state.submissionId, true);
    }
    await featureRepo.markFeatureStatus(featureId);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _flush();   // last-chance flush on screen leave
    super.dispose();
  }
}
```

### `provider.family` keyed on `submissionId`

```dart
final buildingFormNotifierProvider = StateNotifierProvider
  .autoDispose
  .family<BuildingFormNotifier, BuildingFormState, String>((ref, submissionId) { ... });
```

`autoDispose` so switching tabs doesn't leak state. `.family` so each tab has its own notifier instance.

### Field widgets call `notifier.update(...)` only

Each section uses Riverpod's `select` to subscribe to its own slice (so typing in `storeys` doesn't rebuild `cost`):

```dart
final storeys = ref.watch(buildingFormNotifierProvider(submissionId)
  .select((s) => s.storeys));
final notifier = ref.read(buildingFormNotifierProvider(submissionId).notifier);

TextField(
  initialValue: storeys?.toString() ?? '',
  onChanged: (v) {
    final n = int.tryParse(v);
    notifier.update((s) => s.copyWith(storeys: n));
  },
);
```

### Does-not-exist short-circuit

Toggling sets `state.doesNotExist = true`. Other sections read `final disabled = ref.watch(...select((s) => s.doesNotExist));` and pass `enabled: !disabled` to their widgets. Existing values stay in state but are visually disabled. Untoggling re-enables with values intact.

### Edge cases

- **Switching tabs mid-debounce** — `dispose` flushes the pending edit before tearing down.
- **App backgrounded mid-debounce** — Timer survives. Worst case: edit lost if process is killed before 500 ms.
- **Concurrent edits in two tabs** — impossible (only one tab visible).

## 9. Photo capture pipeline

Three thin layers behind `ref.read(photoCaptureControllerProvider).capture(submissionId: ...)`.

### `CameraService` (interface)

```dart
abstract class CameraService {
  Future<String?> capturePhoto();   // returns local path or null on cancel
}
class ImagePickerCameraService implements CameraService { ... }
class FakeCameraService implements CameraService { ... }
```

### `ImageProcessor` (file in / file out)

```dart
Future<({double? lat, double? lng})> resizeAndCopyExif({
  required String sourcePath,
  required String destPath,
});
```

Reads `sourcePath` via `image` package's `decodeJpg`, calls `copyResize(image, width: 1600)` (preserves aspect; branches on orientation for portrait), encodes with `encodeJpg(quality: 85)`, writes bytes. Then opens both files via `native_exif`, copies `GPSLatitude`/`GPSLongitude`/`GPSLatitudeRef`/`GPSLongitudeRef` from source → dest, parses lat/lng to return.

### `PhotoStorageService`

```dart
Future<String> reserveDestPath({required String submissionId});
  // returns getApplicationDocumentsDirectory()/photos/<submissionId>/<uuid>.jpg

Future<void> deleteFile(String path);
```

### `PhotoCaptureController` orchestration

```dart
Future<void> capture({required String submissionId}) async {
  final src = await camera.capturePhoto();
  if (src == null) return;
  final dest = await storage.reserveDestPath(submissionId: submissionId);
  final gps = await processor.resizeAndCopyExif(sourcePath: src, destPath: dest);
  await repo.insert(
    submissionId: submissionId,
    localPath: dest,
    capturedAt: DateTime.now(),
    gpsLat: gps.lat,
    gpsLng: gps.lng,
  );
}
```

`PhotoStrip` watches `photoRepository.watchForSubmission(submissionId)` → reactive thumbnail row. `+ Photo` chip calls `controller.capture(...)`. Tap thumbnail → push `PhotoPreviewScreen`. Long-press thumbnail → confirmation dialog → `repo.delete(...)`.

### Permissions

`image_picker` triggers the Android system camera-permission dialog automatically on first attempt. On denial, `capturePhoto()` returns null (same as cancel). Phase 5 polish adds a "Camera off — go to settings" affordance after repeated denials.

## 10. SubmissionDetailScreen layout

Top-down:

1. **App bar** — back arrow, title (`Building` or `Road` per feature type), subtitle (truncated UUID + distance: `f3e4…a7b2 · 23 m away ✓`).
2. **Tab strip** — horizontal scrollable. Active tab: brand color underline + bold. `+` tab at end (disabled past soft cap of 5). Tap a tab → switches the active form notifier.
3. **Autosave indicator** — slim green-tinted bar always under the tabs. "✓ Saved {n} seconds ago · Offline".
4. **Photo strip** — 60×60 thumbnails, horizontal scroll, `+ Photo` chip at right end. Required-photo badge (red `0/1 required` until ≥1 exists).
5. **Does-not-exist toggle** — first item below the strip. Tan callout when off, red callout + activated switch when on.
6. **Form sections** — Identity → Construction → Cost → Fire-fighting facilities → Fire load. Each in its own `Card`-style container with an uppercase `SECTION HEADER`.
7. **Footer** — readiness status text on the left ("All required fields filled · ready" or "Photo required to mark complete"), Done button on the right (disabled until validation passes).

Field widget patterns:
- Required fields: asterisk on the field label.
- Errors: subtle red border + helper text 500 ms after the invalid edit (live but quiet).
- Multi-select chips: tap toggles. Mutually-exclusive groups (`None` in fire-fighting facilities) clear siblings on selection.
- Cost radio: switching from Exact → Range clears `cost_amount`; reverse clears `cost_estimate_range`.
- Storeys: number input 1–50; >50 = warning ("That's very tall — confirm?") but allowed.

## 11. Validation

`building_form_validator.dart` is pure:

```dart
class ValidationResult {
  final Map<String, String> fieldErrors;   // field name → error message
  final List<String> warnings;              // non-blocking
  bool get isComplete => fieldErrors.isEmpty;
}

ValidationResult validateBuildingForm(BuildingFormState state, int photoCount);
```

### Required fields for `complete` status

When `doesNotExist == false`:
- `buildingName` non-empty
- `ra9514Type` set
- `storeys` ≥ 1
- `material` set
- Either `costAmount` set OR `costEstimateRange` set
- `fireLoad` non-empty
- `photoCount ≥ 1`

When `doesNotExist == true`:
- Only `photoCount ≥ 1`. All other fields waived.

### Inline errors

- Storeys: `>50` → warning, `<1` → error.
- Cost: `costIsExact == true` requires `costAmount > 0`. `costIsExact == false` requires `costEstimateRange` set.
- Fire-fighting facilities: `None` chip mutually exclusive with the others (selecting `None` clears the others; selecting any of the others clears `None`).
- Fire load has no mutually-exclusive sentinel; at least one selection is required.

### RA 9514 dropdown source

Read order each time the form opens: query local Drift `ra_9514_types` table first. If non-empty, use that set (so a future server-driven update to the codes can flow in). If empty (the Phase 1 + Phase 2 seeds don't populate it; Phase 3's seed adds it), fall back to the hardcoded 10-entry list at `lib/features/survey/building_form/domain/ra_9514_fallback.dart`. Never mix sources — first non-empty wins.

### Status flow that drives map color

```
unfilled    → no required field set yet
in_progress → at least one required field set, but not all
complete    → all required + ≥1 photo (or doesNotExist + ≥1 photo)
```

`FeatureRepository.markFeatureStatus(featureId)` queries this submission's row + photos count, derives the status, writes `features.status`. Map screen's `watchFeaturesForAssignment` stream rebuilds the polygon's fill color.

## 12. Distance Override flow

`override_check.dart` (use case):

```dart
sealed class TapResult {
  // Used by map_screen.onPolygonTap.
}

class TapAllowed extends TapResult {
  final double meters;
}

class TapBlocked extends TapResult {
  final double meters;
}

class TapAllowedWithOverride extends TapResult {
  final double meters;
  final String reason;
}

Future<TapResult> checkTap({
  required double userLat,
  required double userLng,
  required Polygon featureGeometry,
  required Future<String?> Function() promptForReason,
}) async {
  final centroid = polygonCentroid(featureGeometry);
  final meters = haversineMeters(userLat, userLng, centroid.lat, centroid.lng);
  if (meters <= 50) return TapAllowed(meters);

  final reason = await promptForReason();
  if (reason == null || reason.trim().isEmpty) return TapBlocked(meters);
  return TapAllowedWithOverride(meters, reason.trim());
}
```

### `centroid.dart` (pure)

Computes the area-weighted centroid of a GeoJSON Polygon (first ring, ignoring holes for Phase 2). Standard formula:

```
A = ½ × Σ(xᵢ × yᵢ₊₁ − xᵢ₊₁ × yᵢ)
Cₓ = (1/6A) × Σ(xᵢ + xᵢ₊₁)(xᵢyᵢ₊₁ − xᵢ₊₁yᵢ)
Cᵧ = (1/6A) × Σ(yᵢ + yᵢ₊₁)(xᵢyᵢ₊₁ − xᵢ₊₁yᵢ)
```

Tested with: a unit square (centroid = 0.5, 0.5), an irregular convex pentagon (known-answer), a degenerate point (returns the point), and a clockwise vs counterclockwise ring (yields same centroid).

### `OverrideReasonDialog`

Modal `AlertDialog`:
- Title: "Override required"
- Body: "You're {distance}m away. Map policy requires ≤50m. Why are you submitting from this distance?"
- TextField (max 200 chars), examples shown as helper text below: `polygon misplaced · couldn't approach safely · unable to verify on foot`
- Buttons: **Cancel** (returns null) / **Continue** (returns the reason; disabled if reason is empty/whitespace).

Stored on `submissions.override_reason`. Phase 4's review screen surfaces it for supervisor attention.

## 13. Error handling matrix

| Surface | Failure | Behavior |
|---|---|---|
| Form save | Drift transaction error | Snackbar: "Couldn't save. Retrying…" — debounce timer reschedules a retry |
| Photo capture | Camera permission denied | Snackbar: "Enable camera permission to take photos" with Settings link |
| Photo capture | OS camera fails (rare) | Snackbar with error message; no photo inserted |
| Photo resize | Source image is corrupt | Snackbar: "Couldn't process this photo. Try again." Source not deleted |
| Photo resize | Out of disk space | Snackbar with `StorageFailure` (existing Phase 0 sealed type) |
| Tab create | Soft cap exceeded (5) | "+" tab disables with tooltip; cannot tap |
| Multi-tab | Last tab deleted | Detail screen pops back to map (no submission left for this feature) |
| Distance check | GPS unavailable | Allow tap; subtitle shows "GPS unavailable — distance not checked" |
| Distance check | GPS accuracy >30 m | Banner: "Weak GPS — distance approximate"; allow tap |
| Override dialog | User dismisses with no reason | Tap is cancelled; map stays open |

## 14. Testing strategy

### Unit
- `centroid_test.dart` — pure math, table-driven cases.
- `building_form_validator_test.dart` — required-field rules, does-not-exist short-circuit, mutually-exclusive chip rules.
- `building_form_state_test.dart` — `copyWith` correctness.

### Integration (Drift in-memory + fakes)
- `migration_v2_to_v3_test.dart` — schema v3 column + still-on FK pragma.
- `submission_repository_test.dart` — `ensureDraftForFeature` idempotence, `createAdditionalSubmission` always creates new, soft-cap counting.
- `building_attributes_repository_test.dart` — upsert round-trip.
- `photo_repository_test.dart` — insert/delete + file unlinking.
- `image_processor_test.dart` — uses fixture `test/fixtures/photo_with_gps.jpg`. Asserts: output ≤1600 px longest edge, output < source size, EXIF lat/lng preserved.
- `photo_capture_controller_test.dart` — orchestrates fake camera + real processor + in-memory repo.
- `building_form_notifier_test.dart` — debounced autosave: edit → wait 500 ms → assert Drift row matches. Switching tabs flushes pending edit.

### Widget
- `submission_tabs_test.dart` — tab switching, soft-cap disabled state.
- `photo_strip_test.dart` — required badge appears with 0 photos, disappears with 1+.
- `building_form_test.dart` — full form widget test with provider overrides; type a value, advance time 600 ms, assert provider state matches.
- `submission_detail_screen_test.dart` — full screen integration: tap polygon → screen opens → fill form → does-not-exist short-circuit hides errors.
- `override_reason_dialog_test.dart` — Continue disabled when reason empty, returns reason when filled.

### Manual field-walk checklist
1. Apply migration `003_override_reason.sql`.
2. Cold install → log in → tap Get Maps (existing flow) → tap a polygon on the map.
3. Land on detail screen with Tab 1 auto-created.
4. Fill all required fields → polygon turns yellow on the map (in_progress).
5. Take photo → wait → photo strip shows thumbnail.
6. Mark "all required" → polygon turns green (complete).
7. Tap "+" → fill Tab 2 differently.
8. Reach 5 tabs → "+" disables.
9. Toggle does-not-exist → fields disable, photo still required, mark complete with one photo.
10. From the map: tap a polygon >50 m from your simulated GPS → modal asks for reason → Continue with reason → reason persisted.

### Not tested
- Real camera output quality (Mapbox emulator camera is canned).
- Real GPS fidelity (geolocator's own tests cover that).

## 15. Phase 2 demo state

After completing Phase 2 implementation:

1. Log in as `admin@admin.com` / `admin123`.
2. Tap Get Maps (already-downloaded assignment from Phase 1).
3. Tap Open map → see 10 red polygons in Brgy. Tisa.
4. Tap any polygon → SubmissionDetailScreen opens with empty Tab 1.
5. Fill the form (name, RA 9514 type, storeys, material, cost, fire load) — autosave indicator updates after each edit. Map polygon turns yellow live.
6. Tap **+ Photo** → system camera opens → take photo → returns to detail screen → thumbnail appears in strip.
7. Required-photo badge clears. Done button enables. Footer says "All required fields filled · ready".
8. Tap Done → returns to map. Polygon now green.
9. Tap **+** tab → fill Tab 2 differently → polygon stays green (any tab complete = complete).
10. Toggle "does not exist" on Tab 2 → fields disable → take a photo → Tab 2 still complete.
11. Pan map far from Brgy. Tisa, simulate a distant GPS position, tap a polygon → modal asks for reason → enter "polygon misplaced" → enter detail screen with the override note recorded.

## 16. Known deferrals (out of Phase 2)

| Item | Target | Why deferred |
|---|---|---|
| Road attribution form | Phase 3 | Distinct schema + UI |
| OLP household survey | Phase 3 | Own module |
| Add new feature (long-press) | Phase 3 | Needs the form working |
| Sync queue / Drift outbox | Phase 4 | Pairs with upload |
| Pre-submit review screen | Phase 4 | End of cycle |
| Photo upload to Supabase Storage | Phase 4 | Pairs with sync queue |
| Camera in-app preview / overlay | Phase 5 | Polish |
| Logout button | Phase 5 | Minor UX |
| iOS support | v2 | Android-first |

## 17. Success criteria for Phase 2

- Fresh install → login → Get Maps (existing) → tap polygon → fill form → take photo → mark complete. End-to-end in under 5 minutes on emulator.
- All Phase 0 + Phase 1 + Phase 2 tests passing (target ~110 total).
- `flutter analyze` clean.
- Map polygon color updates reactively as form fills (no manual refresh).
- App usable offline through the full Phase 2 flow (no network needed for form/photo capture/save).
- Tag `phase-2-form` at the end.
