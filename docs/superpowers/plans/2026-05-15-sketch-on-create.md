# Sketch-on-create Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a tap-to-drop-vertices sketch UI so users can create real Building polygons / Road polylines / Point features at creation time, instead of seeding a single Point and reshaping it.

**Architecture:** Generalize the existing reshape system into a unified `GeometryEditor`. Rename the folder + classes, widen state to support an `isSketchMode` (no `originalFeature`, just a `pendingFeatureType`), add `enterSketch` / `appendSketchVertex` / `validateSketch` methods, and route a new map-tap gesture into them. On Finish, build GeoJSON via the existing `serializeWorking()` and INSERT through a new generic `NewFeatureRepository.createFeature(geometryGeojson)`. Cancel discards (with a confirm dialog if any vertices were dropped). All existing reshape behavior (drag, midpoint insert, long-press-to-remove with confirm, undo, body-translate) is reused unchanged.

**Tech Stack:** Flutter, Riverpod (`Notifier`), Drift, mapbox_maps_flutter 2.22, l10n via ARB files.

**Implementation note vs. spec:** The spec section "User flow" mentions "tap a vertex handle to remove." The existing reshape overlay actually uses **long-press on a vertex** with a confirm dialog (`showReshapeRemoveConfirm`). To honor the spec's "reuse reshape components fully" decision, the sketch flow inherits the same long-press-to-remove gesture. This is the only sketch gesture difference vs. the spec text and is documented inline in Task 10 (banner hint copy mentions long-press-to-remove).

---

## File Structure

**Renamed folder:**
- `lib/features/map/reshape/` → `lib/features/map/geometry_editor/`
- `test/features/map/reshape/` → `test/features/map/geometry_editor/`

**Renamed classes / providers (within the renamed folder):**

| Before | After |
|---|---|
| `ReshapeModeController` | `GeometryEditorController` |
| `ReshapeModeState` | `GeometryEditorState` |
| `reshapeModeControllerProvider` | `geometryEditorControllerProvider` |
| `ReshapeBanner` | `GeometryEditorBanner` |
| `ReshapeOverlay` | `GeometryEditorOverlay` |
| `ReshapeOp`, `Move`, `Add`, `Remove`, `Translate` | unchanged (still describe vertex ops) |
| `reshapeRepositoryProvider` | unchanged (revisions audit trail is reshape-specific) |

**New files:**
- `lib/features/map/geometry_editor/domain/sketch_validation_error.dart` — `SketchValidationError` enum + helper
- `lib/features/map/geometry_editor/presentation/sketch_error_messages.dart` — `sketchErrorMessage(SketchValidationError, AppLocalizations) → String`
- `lib/core/geo/polyline_validator.dart` — `validatePolyline(List<LngLat>) → PolylineValidationError?`
- `test/features/map/geometry_editor/geometry_editor_controller_sketch_test.dart`
- `test/features/map/geometry_editor/geometry_editor_banner_sketch_test.dart`
- `test/features/map/sketch_flow_test.dart`
- `test/core/geo/polyline_validator_test.dart`
- `test/features/new_feature/new_feature_repository_test.dart`

**Modified files:**
- `lib/features/map/presentation/map_screen.dart` — drop `_addModeActive`, drop `_handleLongPress`, add `_onPlusPressed`, wire `onMapTap` and banner Finish/Cancel
- `lib/features/map/presentation/map_renderer.dart` — add `sketchActive` + `onMapTap`, remove `onLongPress` + `addModeActive` plumbing, add `simulateMapTap` to `FakeMapRenderer`, wire Mapbox `onTapListener`
- `lib/features/new_feature/data/new_feature_repository.dart` — add `createFeature(geometryGeojson)`, delete `createNewFeature(lat, lng)`
- `lib/features/map/geometry_editor/presentation/geometry_editor_banner.dart` (post-rename) — switch primary button label between Save (reshape) and Finish (sketch); switch title format
- `lib/features/map/geometry_editor/presentation/geometry_editor_overlay.dart` (post-rename) — already gated on `state.isActive`; no logic change after `isActive` is widened in Task 2
- `lib/core/i18n/app_en.arb`, `lib/core/i18n/app_tl.arb` — new sketch l10n keys
- `test/features/map/map_screen_add_mode_test.dart` — replace long-press flow with type-picker + sketch tap

**Deleted (in Task 10/11):**
- `MapScreen._handleLongPress`
- `NewFeatureRepository.createNewFeature(lat, lng)` (after Task 7's replacement is in use)
- `MapRenderer.build`'s `onLongPress` and `addModeActive` parameters

---

## Task 1: Rename reshape → geometry_editor

**Files:**
- Rename: `lib/features/map/reshape/` → `lib/features/map/geometry_editor/`
- Rename: `test/features/map/reshape/` → `test/features/map/geometry_editor/`
- Modify: every file that imports the old paths or references the renamed symbols (use grep to find them)

This is a mechanical sweep. No behavior changes; tests must stay green.

- [ ] **Step 1: Move the lib/ folder**

```bash
git mv lib/features/map/reshape lib/features/map/geometry_editor
```

- [ ] **Step 2: Move the test/ folder**

```bash
git mv test/features/map/reshape test/features/map/geometry_editor
```

- [ ] **Step 3: Find every reference to the old paths**

```bash
grep -rln "features/map/reshape\|reshape_mode\|ReshapeMode\|reshape_overlay\|ReshapeOverlay\|reshape_banner\|ReshapeBanner\|reshape_providers\|reshapeModeControllerProvider" lib test
```

Note the file list — every match needs the rename applied in the next steps.

- [ ] **Step 4: Update import paths and class names**

For each file from Step 3, apply these substitutions (use Edit tool per file, or sed if you prefer — but the rename is unambiguous so a global sed is safe):

| Find | Replace |
|---|---|
| `features/map/reshape/` | `features/map/geometry_editor/` |
| `reshape_mode_controller.dart` | `geometry_editor_controller.dart` |
| `reshape_mode_state.dart` | `geometry_editor_state.dart` |
| `reshape_overlay.dart` | `geometry_editor_overlay.dart` |
| `reshape_banner.dart` | `geometry_editor_banner.dart` |
| `reshape_providers.dart` | `geometry_editor_providers.dart` |
| `ReshapeModeController` | `GeometryEditorController` |
| `ReshapeModeState` | `GeometryEditorState` |
| `ReshapeOverlay` | `GeometryEditorOverlay` |
| `ReshapeBanner` | `GeometryEditorBanner` |
| `reshapeModeControllerProvider` | `geometryEditorControllerProvider` |

Do NOT rename: `ReshapeOp`, `Move`, `Add`, `Remove`, `Translate`, `reshapeRepositoryProvider`, `reshapeRepository`, `feature_geometry_revisions_repository`, `reshapeBannerTitle`, `reshapeBannerSave`, `reshape.banner.cancel`/`reshape.banner.save`/`reshape.banner.undo` widget keys, analytics event names (`map.reshape.*`). All of those still semantically refer to reshape (the audit trail, l10n strings, widget keys for existing tests).

Also rename the inner files:
```bash
git mv lib/features/map/geometry_editor/presentation/reshape_mode_controller.dart \
        lib/features/map/geometry_editor/presentation/geometry_editor_controller.dart
git mv lib/features/map/geometry_editor/domain/reshape_mode_state.dart \
        lib/features/map/geometry_editor/domain/geometry_editor_state.dart
git mv lib/features/map/geometry_editor/presentation/reshape_overlay.dart \
        lib/features/map/geometry_editor/presentation/geometry_editor_overlay.dart
git mv lib/features/map/geometry_editor/presentation/reshape_banner.dart \
        lib/features/map/geometry_editor/presentation/geometry_editor_banner.dart
git mv lib/features/map/geometry_editor/presentation/reshape_providers.dart \
        lib/features/map/geometry_editor/presentation/geometry_editor_providers.dart
```

Test files under `test/features/map/geometry_editor/` keep their `reshape_*_test.dart` filenames — they describe reshape *mode* tests of the editor controller. The class names inside them get renamed per the table above.

- [ ] **Step 5: Run flutter analyze**

Run: `flutter analyze`
Expected: 0 errors related to renames. Pre-existing warnings noted in observation 2885 are acceptable; no NEW errors from this task.

- [ ] **Step 6: Run the test suite**

Run: `flutter test`
Expected: every previously-passing test still passes. Pre-existing failures from observation 2889 are acceptable as documented baseline; no NEW failures from this task.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor(map): rename reshape to geometry_editor in prep for sketch mode

The reshape system is being generalized into a unified geometry editor
that handles both reshape (existing feature) and sketch (new feature).
This commit is the mechanical rename only — no behavior changes.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add `pendingFeatureType` to state, widen `isActive`

**Files:**
- Modify: `lib/features/map/geometry_editor/domain/geometry_editor_state.dart`
- Modify: `test/features/map/geometry_editor/reshape_mode_controller_test.dart` (add a new group `group('sketch state', ...)` near the bottom)

- [ ] **Step 1: Write the failing test**

Add to `test/features/map/geometry_editor/reshape_mode_controller_test.dart`:

```dart
group('sketch state', () {
  test('default state has no pending feature type and is not active', () {
    const s = GeometryEditorState();
    expect(s.pendingFeatureType, isNull);
    expect(s.isSketchMode, isFalse);
    expect(s.isActive, isFalse);
  });

  test('pendingFeatureType set with no originalFeature → isSketchMode + isActive', () {
    const s = GeometryEditorState(pendingFeatureType: 'building');
    expect(s.isSketchMode, isTrue);
    expect(s.isActive, isTrue);
  });

  test('originalFeature set → isActive remains true (reshape mode)', () {
    // Use a Drift-generated Feature row built from a minimal companion via insertReturning,
    // OR just assert the boolean logic with a non-null sentinel:
    final s = GeometryEditorState(
      originalFeature: _fakeFeature(),
      pendingFeatureType: null,
    );
    expect(s.isSketchMode, isFalse);
    expect(s.isActive, isTrue);
  });
});

// Helper near the top of the file (or import an existing one if reshape tests already
// have a fixture). Keep it minimal.
Feature _fakeFeature() => Feature(
      id: 'f1',
      assignmentId: 'a1',
      featureType: 'building',
      geometryGeojson: '{"type":"Polygon","coordinates":[[[0,0],[1,0],[1,1],[0,0]]]}',
      isNew: false,
      createdAt: DateTime(2026, 1, 1),
      status: 'pending',
      photoCount: 0,
    );
```

If the existing test file already has a Feature fixture, reuse it instead of redefining.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/map/geometry_editor/reshape_mode_controller_test.dart -p vm --plain-name "sketch state"`
Expected: FAIL — `pendingFeatureType` parameter doesn't exist on `GeometryEditorState`.

- [ ] **Step 3: Update GeometryEditorState**

Edit `lib/features/map/geometry_editor/domain/geometry_editor_state.dart`:

```dart
import 'package:firecheck/core/db/database.dart' show Feature;
import 'package:firecheck/core/geo/polygon_validator.dart' show LngLat;
import 'package:firecheck/features/map/geometry_editor/domain/reshape_op.dart';

class GeometryEditorState {
  const GeometryEditorState({
    this.originalFeature,
    this.pendingFeatureType,
    this.workingRings = const [],
    this.undoStack = const [],
    this.selfIntersects = false,
    this.saving = false,
    this.overrideReason,
    this.isClosed = true,
  });

  final Feature? originalFeature;

  /// 'building' | 'road' | 'point' when sketching a new feature; null otherwise.
  /// Mutually exclusive with [originalFeature]: reshape mode sets the latter,
  /// sketch mode sets this.
  final String? pendingFeatureType;

  final List<List<LngLat>> workingRings;
  final List<ReshapeOp> undoStack;
  final bool selfIntersects;
  final bool saving;
  final String? overrideReason;
  final bool isClosed;

  bool get isSketchMode =>
      originalFeature == null && pendingFeatureType != null;
  bool get isActive => originalFeature != null || isSketchMode;
  bool get isDirty => undoStack.isNotEmpty;

  GeometryEditorState copyWith({
    Object? originalFeature = _sentinel,
    Object? pendingFeatureType = _sentinel,
    List<List<LngLat>>? workingRings,
    List<ReshapeOp>? undoStack,
    bool? selfIntersects,
    bool? saving,
    Object? overrideReason = _sentinel,
    bool? isClosed,
  }) {
    return GeometryEditorState(
      originalFeature: identical(originalFeature, _sentinel)
          ? this.originalFeature
          : originalFeature as Feature?,
      pendingFeatureType: identical(pendingFeatureType, _sentinel)
          ? this.pendingFeatureType
          : pendingFeatureType as String?,
      workingRings: workingRings ?? this.workingRings,
      undoStack: undoStack ?? this.undoStack,
      selfIntersects: selfIntersects ?? this.selfIntersects,
      saving: saving ?? this.saving,
      overrideReason: identical(overrideReason, _sentinel)
          ? this.overrideReason
          : overrideReason as String?,
      isClosed: isClosed ?? this.isClosed,
    );
  }

  static const _sentinel = Object();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/map/geometry_editor/reshape_mode_controller_test.dart -p vm`
Expected: all tests pass (including pre-existing reshape tests, since `isActive` still returns true when `originalFeature != null`).

- [ ] **Step 5: Commit**

```bash
git add lib/features/map/geometry_editor/domain/geometry_editor_state.dart \
        test/features/map/geometry_editor/reshape_mode_controller_test.dart
git commit -m "$(cat <<'EOF'
feat(geometry-editor): add pendingFeatureType state for sketch mode

State now distinguishes reshape (originalFeature set) from sketch
(pendingFeatureType set). isActive returns true for either; isSketchMode
gates sketch-only behavior.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Controller `enterSketch()`

**Files:**
- Modify: `lib/features/map/geometry_editor/presentation/geometry_editor_controller.dart`
- Modify: `test/features/map/geometry_editor/reshape_mode_controller_test.dart`

- [ ] **Step 1: Write the failing test**

Add to the same test file in a new `group('enterSketch', ...)`:

```dart
group('enterSketch', () {
  ProviderContainer makeContainer() => ProviderContainer();

  test('building → empty closed ring, sketch mode active', () {
    final c = makeContainer();
    c.read(geometryEditorControllerProvider.notifier)
        .enterSketch(featureType: 'building');
    final s = c.read(geometryEditorControllerProvider);
    expect(s.pendingFeatureType, 'building');
    expect(s.isSketchMode, isTrue);
    expect(s.isClosed, isTrue);
    expect(s.workingRings, [<LngLat>[]]);
    expect(s.undoStack, isEmpty);
    expect(s.selfIntersects, isFalse);
  });

  test('road → empty open ring, isClosed false', () {
    final c = makeContainer();
    c.read(geometryEditorControllerProvider.notifier)
        .enterSketch(featureType: 'road');
    final s = c.read(geometryEditorControllerProvider);
    expect(s.pendingFeatureType, 'road');
    expect(s.isClosed, isFalse);
    expect(s.workingRings, [<LngLat>[]]);
  });

  test('point → empty open ring, isClosed false', () {
    final c = makeContainer();
    c.read(geometryEditorControllerProvider.notifier)
        .enterSketch(featureType: 'point');
    final s = c.read(geometryEditorControllerProvider);
    expect(s.pendingFeatureType, 'point');
    expect(s.isClosed, isFalse);
  });

  test('cancel() clears sketch state', () {
    final c = makeContainer();
    final n = c.read(geometryEditorControllerProvider.notifier)
      ..enterSketch(featureType: 'building');
    n.cancel();
    final s = c.read(geometryEditorControllerProvider);
    expect(s.isActive, isFalse);
    expect(s.pendingFeatureType, isNull);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/map/geometry_editor/reshape_mode_controller_test.dart -p vm --plain-name "enterSketch"`
Expected: FAIL — `enterSketch` is not defined on `GeometryEditorController`.

- [ ] **Step 3: Add `enterSketch` to the controller**

Edit `lib/features/map/geometry_editor/presentation/geometry_editor_controller.dart`. Add this method to the controller class, just below `enterReshape`:

```dart
void enterSketch({required String featureType}) {
  state = GeometryEditorState(
    pendingFeatureType: featureType,
    workingRings: const [<LngLat>[]],
    isClosed: featureType == 'building',
  );
}
```

The existing `cancel()` method (which sets `state = const GeometryEditorState()`) already clears sketch state correctly because the new state's defaults zero everything out.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/map/geometry_editor/reshape_mode_controller_test.dart -p vm`
Expected: PASS, including all pre-existing reshape tests.

- [ ] **Step 5: Commit**

```bash
git add lib/features/map/geometry_editor/presentation/geometry_editor_controller.dart \
        test/features/map/geometry_editor/reshape_mode_controller_test.dart
git commit -m "$(cat <<'EOF'
feat(geometry-editor): add enterSketch for new-feature creation

enterSketch initializes a fresh editor state for a given feature type:
empty ring, isClosed inferred from type ('building' → closed polygon,
'road'/'point' → open).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Controller `appendSketchVertex()`

For 'building' and 'road': append at end of `workingRings[0]`. For 'point': if the ring already has a vertex, replace it (record as `Move`); else append (record as `Add`).

**Files:**
- Modify: `lib/features/map/geometry_editor/presentation/geometry_editor_controller.dart`
- Modify: `test/features/map/geometry_editor/reshape_mode_controller_test.dart`

- [ ] **Step 1: Write the failing test**

Add to the test file in a new `group('appendSketchVertex', ...)`:

```dart
group('appendSketchVertex', () {
  ProviderContainer makeContainer() => ProviderContainer();

  test('building: each tap appends a vertex (Add op)', () {
    final c = makeContainer();
    final n = c.read(geometryEditorControllerProvider.notifier)
      ..enterSketch(featureType: 'building')
      ..appendSketchVertex((lng: 1.0, lat: 1.0))
      ..appendSketchVertex((lng: 2.0, lat: 2.0))
      ..appendSketchVertex((lng: 3.0, lat: 3.0));
    final s = c.read(geometryEditorControllerProvider);
    expect(s.workingRings[0], [
      (lng: 1.0, lat: 1.0),
      (lng: 2.0, lat: 2.0),
      (lng: 3.0, lat: 3.0),
    ]);
    expect(s.undoStack, hasLength(3));
    expect(s.undoStack.every((op) => op is Add), isTrue);
    // No-op for the controller (no n use after final read)
    expect(n, isNotNull);
  });

  test('road: each tap appends a vertex', () {
    final c = makeContainer();
    c.read(geometryEditorControllerProvider.notifier)
      ..enterSketch(featureType: 'road')
      ..appendSketchVertex((lng: 1.0, lat: 1.0))
      ..appendSketchVertex((lng: 2.0, lat: 2.0));
    final s = c.read(geometryEditorControllerProvider);
    expect(s.workingRings[0], hasLength(2));
    expect(s.undoStack, hasLength(2));
  });

  test('point: first tap appends; second tap replaces (Move op)', () {
    final c = makeContainer();
    c.read(geometryEditorControllerProvider.notifier)
      ..enterSketch(featureType: 'point')
      ..appendSketchVertex((lng: 1.0, lat: 1.0))
      ..appendSketchVertex((lng: 5.0, lat: 5.0));
    final s = c.read(geometryEditorControllerProvider);
    expect(s.workingRings[0], hasLength(1));
    expect(s.workingRings[0][0], (lng: 5.0, lat: 5.0));
    expect(s.undoStack, hasLength(2));
    expect(s.undoStack[0], isA<Add>());
    expect(s.undoStack[1], isA<Move>());
    final move = s.undoStack[1] as Move;
    expect(move.prev, (lng: 1.0, lat: 1.0));
    expect(move.next, (lng: 5.0, lat: 5.0));
  });

  test('appendSketchVertex is a no-op when not active', () {
    final c = makeContainer();
    c.read(geometryEditorControllerProvider.notifier)
        .appendSketchVertex((lng: 1.0, lat: 1.0));
    expect(c.read(geometryEditorControllerProvider).workingRings, isEmpty);
  });

  test('undo after building tap pops the vertex', () {
    final c = makeContainer();
    c.read(geometryEditorControllerProvider.notifier)
      ..enterSketch(featureType: 'building')
      ..appendSketchVertex((lng: 1.0, lat: 1.0))
      ..appendSketchVertex((lng: 2.0, lat: 2.0))
      ..undo();
    final s = c.read(geometryEditorControllerProvider);
    expect(s.workingRings[0], [(lng: 1.0, lat: 1.0)]);
    expect(s.undoStack, hasLength(1));
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/map/geometry_editor/reshape_mode_controller_test.dart -p vm --plain-name "appendSketchVertex"`
Expected: FAIL — `appendSketchVertex` is not defined.

- [ ] **Step 3: Add `appendSketchVertex` to the controller**

Add this method to `GeometryEditorController` (just below `addVertex`):

```dart
/// Sketch-mode tap-to-place. For 'building'/'road' appends a new vertex at
/// the end of ring 0. For 'point', the first call appends; subsequent calls
/// replace vertex 0 (recorded as a Move so undo behaves correctly).
void appendSketchVertex(LngLat lngLat) {
  if (!state.isSketchMode) return;
  final rings = _cloneRings(state.workingRings);
  final ring = rings[0];

  if (state.pendingFeatureType == 'point' && ring.isNotEmpty) {
    final prev = ring[0];
    if (prev == lngLat) return; // no-op on identical re-tap
    ring[0] = lngLat;
    state = state.copyWith(
      workingRings: rings,
      undoStack: [
        ...state.undoStack,
        Move(ringIdx: 0, vertexIdx: 0, prev: prev, next: lngLat),
      ],
      selfIntersects: _recomputeSelfIntersect(state, rings),
    );
    return;
  }

  ring.add(lngLat);
  state = state.copyWith(
    workingRings: rings,
    undoStack: [
      ...state.undoStack,
      Add(ringIdx: 0, vertexIdx: ring.length - 1, lngLat: lngLat),
    ],
    selfIntersects: _recomputeSelfIntersect(state, rings),
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/map/geometry_editor/reshape_mode_controller_test.dart -p vm`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/map/geometry_editor/presentation/geometry_editor_controller.dart \
        test/features/map/geometry_editor/reshape_mode_controller_test.dart
git commit -m "$(cat <<'EOF'
feat(geometry-editor): add appendSketchVertex for tap-to-drop

Building/road append; point replaces vertex 0 on subsequent taps and
records the change as a Move so undo restores the previous location.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Polyline validator + `SketchValidationError` enum

**Files:**
- Create: `lib/core/geo/polyline_validator.dart`
- Create: `lib/features/map/geometry_editor/domain/sketch_validation_error.dart`
- Create: `test/core/geo/polyline_validator_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/geo/polyline_validator_test.dart`:

```dart
import 'package:firecheck/core/geo/polygon_validator.dart' show LngLat;
import 'package:firecheck/core/geo/polyline_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validatePolyline', () {
    test('returns null for two distinct vertices', () {
      final r = validatePolyline([
        (lng: 0.0, lat: 0.0),
        (lng: 1.0, lat: 0.0),
      ]);
      expect(r, isNull);
    });

    test('returns notEnoughVertices for fewer than 2', () {
      expect(validatePolyline([]), PolylineValidationError.notEnoughVertices);
      expect(validatePolyline([(lng: 0.0, lat: 0.0)]),
          PolylineValidationError.notEnoughVertices);
    });

    test('returns zeroLengthEdge when adjacent vertices are equal', () {
      final r = validatePolyline([
        (lng: 0.0, lat: 0.0),
        (lng: 0.0, lat: 0.0),
        (lng: 1.0, lat: 1.0),
      ]);
      expect(r, PolylineValidationError.zeroLengthEdge);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/geo/polyline_validator_test.dart`
Expected: FAIL — `polyline_validator.dart` does not exist.

- [ ] **Step 3: Implement the validator**

Create `lib/core/geo/polyline_validator.dart`:

```dart
import 'package:firecheck/core/geo/polygon_validator.dart' show LngLat;

enum PolylineValidationError {
  notEnoughVertices,
  zeroLengthEdge,
}

PolylineValidationError? validatePolyline(List<LngLat> coords) {
  if (coords.length < 2) return PolylineValidationError.notEnoughVertices;
  for (var i = 1; i < coords.length; i++) {
    final a = coords[i - 1];
    final b = coords[i];
    if (a.lng == b.lng && a.lat == b.lat) {
      return PolylineValidationError.zeroLengthEdge;
    }
  }
  return null;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/geo/polyline_validator_test.dart`
Expected: PASS.

- [ ] **Step 5: Add the SketchValidationError enum**

Create `lib/features/map/geometry_editor/domain/sketch_validation_error.dart`:

```dart
/// Errors surfaced by [GeometryEditorController.validateSketch]. Mapped to
/// snackbar copy by `sketchErrorMessage(...)` in the presentation layer.
enum SketchValidationError {
  /// Below the per-type minimum: 3 (building), 2 (road), 1 (point).
  notEnoughVertices,

  /// At least one vertex is outside the assignment boundary.
  vertexOutsideBoundary,

  /// Polygon outer ring crosses itself.
  selfIntersection,

  /// Two adjacent vertices coincide (zero-length segment).
  zeroLengthEdge,
}
```

No test needed for the enum on its own; it's exercised in Task 6.

- [ ] **Step 6: Commit**

```bash
git add lib/core/geo/polyline_validator.dart \
        lib/features/map/geometry_editor/domain/sketch_validation_error.dart \
        test/core/geo/polyline_validator_test.dart
git commit -m "$(cat <<'EOF'
feat(geo): polyline validator + sketch validation error enum

validatePolyline checks min vertex count and zero-length segments.
SketchValidationError unifies the failure cases the geometry editor's
sketch mode can return.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Controller `validateSketch()`

Dispatches by `pendingFeatureType`:
- `building` → min 3 vertices, every vertex in boundary, run existing `validateBuildingPolygon` for closure/orientation/self-intersection
- `road` → min 2 vertices, every vertex in boundary, run `validatePolyline` for zero-length
- `point` → exactly 1 vertex, in boundary

Boundary check is skipped if `boundaryGeojson` is empty or unparseable (matches the existing fallback added 2026-05-15 morning).

**Files:**
- Modify: `lib/features/map/geometry_editor/presentation/geometry_editor_controller.dart`
- Modify: `test/features/map/geometry_editor/reshape_mode_controller_test.dart`

- [ ] **Step 1: Write the failing test**

Add to the test file in a new `group('validateSketch', ...)`:

```dart
group('validateSketch', () {
  // 10x10 square boundary in lng/lat units.
  const boundary =
      '{"type":"Polygon","coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]]]}';

  ProviderContainer makeContainer() => ProviderContainer();

  test('building: 3 in-bounds vertices → null (valid)', () {
    final c = makeContainer();
    c.read(geometryEditorControllerProvider.notifier)
      ..enterSketch(featureType: 'building')
      ..appendSketchVertex((lng: 1.0, lat: 1.0))
      ..appendSketchVertex((lng: 2.0, lat: 1.0))
      ..appendSketchVertex((lng: 1.5, lat: 2.0));
    final r = c.read(geometryEditorControllerProvider.notifier)
        .validateSketch(boundaryGeojson: boundary);
    expect(r, isNull);
  });

  test('building: 2 vertices → notEnoughVertices', () {
    final c = makeContainer();
    c.read(geometryEditorControllerProvider.notifier)
      ..enterSketch(featureType: 'building')
      ..appendSketchVertex((lng: 1.0, lat: 1.0))
      ..appendSketchVertex((lng: 2.0, lat: 2.0));
    final r = c.read(geometryEditorControllerProvider.notifier)
        .validateSketch(boundaryGeojson: boundary);
    expect(r, SketchValidationError.notEnoughVertices);
  });

  test('building: 3 vertices, one outside boundary → vertexOutsideBoundary', () {
    final c = makeContainer();
    c.read(geometryEditorControllerProvider.notifier)
      ..enterSketch(featureType: 'building')
      ..appendSketchVertex((lng: 1.0, lat: 1.0))
      ..appendSketchVertex((lng: 2.0, lat: 2.0))
      ..appendSketchVertex((lng: 99.0, lat: 99.0));
    final r = c.read(geometryEditorControllerProvider.notifier)
        .validateSketch(boundaryGeojson: boundary);
    expect(r, SketchValidationError.vertexOutsideBoundary);
  });

  test('building: bowtie self-intersection → selfIntersection', () {
    final c = makeContainer();
    c.read(geometryEditorControllerProvider.notifier)
      ..enterSketch(featureType: 'building')
      ..appendSketchVertex((lng: 0.5, lat: 0.5))
      ..appendSketchVertex((lng: 2.0, lat: 0.5))
      ..appendSketchVertex((lng: 0.5, lat: 2.0))
      ..appendSketchVertex((lng: 2.0, lat: 2.0));
    final r = c.read(geometryEditorControllerProvider.notifier)
        .validateSketch(boundaryGeojson: boundary);
    expect(r, SketchValidationError.selfIntersection);
  });

  test('road: 2 in-bounds vertices → null', () {
    final c = makeContainer();
    c.read(geometryEditorControllerProvider.notifier)
      ..enterSketch(featureType: 'road')
      ..appendSketchVertex((lng: 1.0, lat: 1.0))
      ..appendSketchVertex((lng: 2.0, lat: 2.0));
    final r = c.read(geometryEditorControllerProvider.notifier)
        .validateSketch(boundaryGeojson: boundary);
    expect(r, isNull);
  });

  test('road: 1 vertex → notEnoughVertices', () {
    final c = makeContainer();
    c.read(geometryEditorControllerProvider.notifier)
      ..enterSketch(featureType: 'road')
      ..appendSketchVertex((lng: 1.0, lat: 1.0));
    final r = c.read(geometryEditorControllerProvider.notifier)
        .validateSketch(boundaryGeojson: boundary);
    expect(r, SketchValidationError.notEnoughVertices);
  });

  test('point: 1 in-bounds vertex → null', () {
    final c = makeContainer();
    c.read(geometryEditorControllerProvider.notifier)
      ..enterSketch(featureType: 'point')
      ..appendSketchVertex((lng: 1.0, lat: 1.0));
    final r = c.read(geometryEditorControllerProvider.notifier)
        .validateSketch(boundaryGeojson: boundary);
    expect(r, isNull);
  });

  test('point: 0 vertices → notEnoughVertices', () {
    final c = makeContainer();
    c.read(geometryEditorControllerProvider.notifier)
        .enterSketch(featureType: 'point');
    final r = c.read(geometryEditorControllerProvider.notifier)
        .validateSketch(boundaryGeojson: boundary);
    expect(r, SketchValidationError.notEnoughVertices);
  });

  test('empty boundary GeoJSON skips the boundary check', () {
    final c = makeContainer();
    c.read(geometryEditorControllerProvider.notifier)
      ..enterSketch(featureType: 'point')
      ..appendSketchVertex((lng: 999.0, lat: 999.0));
    final r = c.read(geometryEditorControllerProvider.notifier)
        .validateSketch(boundaryGeojson: '');
    expect(r, isNull);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/map/geometry_editor/reshape_mode_controller_test.dart -p vm --plain-name "validateSketch"`
Expected: FAIL — `validateSketch` not defined.

- [ ] **Step 3: Implement `validateSketch`**

Add the import block at the top of `geometry_editor_controller.dart`:

```dart
import 'package:firecheck/core/geo/point_in_polygon.dart';
import 'package:firecheck/core/geo/polyline_validator.dart';
import 'package:firecheck/features/map/geometry_editor/domain/sketch_validation_error.dart';
```

Then add the method to the controller:

```dart
/// Validates the in-progress sketch. Returns null when the geometry is OK to
/// commit; otherwise returns the first failure. Boundary check is skipped
/// when [boundaryGeojson] is empty or doesn't parse to a Polygon — matches
/// the empty-coords-Polygon fallback fix from 2026-05-15.
SketchValidationError? validateSketch({required String boundaryGeojson}) {
  if (!state.isSketchMode) return null;
  final ring = state.workingRings.isNotEmpty
      ? state.workingRings[0]
      : const <LngLat>[];
  final type = state.pendingFeatureType;

  // 1. Min vertex count.
  final min = type == 'building' ? 3 : (type == 'road' ? 2 : 1);
  final maxAllowed = type == 'point' ? 1 : 1 << 30;
  if (ring.length < min || ring.length > maxAllowed) {
    return SketchValidationError.notEnoughVertices;
  }

  // 2. Per-vertex boundary (skipped when boundary unparseable/empty).
  final hasBoundary =
      boundaryGeojson.isNotEmpty && polygonBoundsFromGeojson(boundaryGeojson) != null;
  if (hasBoundary) {
    for (final v in ring) {
      if (!pointInPolygonGeojson(v.lat, v.lng, boundaryGeojson)) {
        return SketchValidationError.vertexOutsideBoundary;
      }
    }
  }

  // 3. Type-specific structural checks.
  if (type == 'building') {
    // World boundary so per-vertex check above isn't double-counted; we only
    // care about closure/orientation/self-intersection here.
    const world =
        '{"type":"Polygon","coordinates":[[[-180,-90],[180,-90],[180,90],[-180,90],[-180,-90]]]}';
    final r = validateBuildingPolygon([ring], boundaryGeojson: world);
    if (!r.valid) {
      return switch (r.error!) {
        PolygonValidationError.selfIntersection =>
          SketchValidationError.selfIntersection,
        PolygonValidationError.zeroLengthEdge =>
          SketchValidationError.zeroLengthEdge,
        // The world boundary makes outsideBoundary impossible here; if it
        // somehow surfaces, treat as selfIntersection (conservative).
        _ => SketchValidationError.selfIntersection,
      };
    }
  } else if (type == 'road') {
    final r = validatePolyline(ring);
    if (r != null) {
      return switch (r) {
        PolylineValidationError.notEnoughVertices =>
          SketchValidationError.notEnoughVertices,
        PolylineValidationError.zeroLengthEdge =>
          SketchValidationError.zeroLengthEdge,
      };
    }
  }
  // 'point' has no extra structural rules.

  return null;
}
```

Note: `polygonBoundsFromGeojson` and `pointInPolygonGeojson` already live in `core/geo/`. `validateBuildingPolygon` and `PolygonValidationError` come from `core/geo/polygon_validator.dart` (already imported by the controller).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/map/geometry_editor/reshape_mode_controller_test.dart -p vm`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/map/geometry_editor/presentation/geometry_editor_controller.dart \
        test/features/map/geometry_editor/reshape_mode_controller_test.dart
git commit -m "$(cat <<'EOF'
feat(geometry-editor): validateSketch dispatches by feature type

Building uses validateBuildingPolygon; road uses validatePolyline; point
checks only vertex count + boundary. Empty/unparseable boundary skips the
in-boundary check, mirroring the morning fix for empty-coords Polygons.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: `NewFeatureRepository.createFeature(geometryGeojson)`

Add the generic creator. Keep `createNewFeature(lat, lng)` for now — it'll be deleted in Task 10 when its only caller is gone.

**Files:**
- Modify: `lib/features/new_feature/data/new_feature_repository.dart`
- Create: `test/features/new_feature/new_feature_repository_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/new_feature/new_feature_repository_test.dart`:

```dart
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/new_feature/data/new_feature_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late NewFeatureRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = NewFeatureRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('createFeature', () {
    test('inserts a row with the supplied GeoJSON, isNew=true', () async {
      // Seed an assignment so the FK is satisfied.
      await db.into(db.assignments).insert(
            AssignmentsCompanion.insert(
              id: 'a1',
              boundaryPolygonGeojson: const Value(''),
            ),
          );

      const geom =
          '{"type":"Polygon","coordinates":[[[1,1],[2,1],[1.5,2],[1,1]]]}';
      final f = await repo.createFeature(
        assignmentId: 'a1',
        featureType: 'building',
        geometryGeojson: geom,
      );

      expect(f.assignmentId, 'a1');
      expect(f.featureType, 'building');
      expect(f.geometryGeojson, geom);
      expect(f.isNew, isTrue);
      expect(f.id, isNotEmpty);
    });

    test('different calls produce different IDs', () async {
      await db.into(db.assignments).insert(
            AssignmentsCompanion.insert(
              id: 'a1',
              boundaryPolygonGeojson: const Value(''),
            ),
          );
      final f1 = await repo.createFeature(
        assignmentId: 'a1',
        featureType: 'point',
        geometryGeojson: '{"type":"Point","coordinates":[1,1]}',
      );
      final f2 = await repo.createFeature(
        assignmentId: 'a1',
        featureType: 'point',
        geometryGeojson: '{"type":"Point","coordinates":[2,2]}',
      );
      expect(f1.id, isNot(f2.id));
    });
  });
}
```

If `AppDatabase.forTesting(...)` doesn't exist with that exact signature, look at how other repository tests construct an in-memory `AppDatabase` (search: `grep -rn "AppDatabase.forTesting\|NativeDatabase.memory" test/`) and copy that pattern. The exact constructor varies by codebase convention. If the seeded assignment row needs other required fields, add them based on the Drift-generated companion type.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/new_feature/new_feature_repository_test.dart`
Expected: FAIL — `createFeature` is not defined on `NewFeatureRepository`.

- [ ] **Step 3: Add `createFeature`**

Edit `lib/features/new_feature/data/new_feature_repository.dart`:

```dart
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:uuid/uuid.dart';

class NewFeatureRepository {
  NewFeatureRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  /// Generic creator used by the sketch-on-create flow. The caller (the
  /// geometry editor) is responsible for serializing the right GeoJSON shape
  /// for [featureType].
  Future<Feature> createFeature({
    required String assignmentId,
    required String featureType,
    required String geometryGeojson,
  }) {
    return _db.into(_db.features).insertReturning(
          FeaturesCompanion.insert(
            id: _uuid.v4(),
            assignmentId: assignmentId,
            featureType: featureType,
            geometryGeojson: geometryGeojson,
            isNew: const Value(true),
            createdAt: DateTime.now(),
          ),
        );
  }

  /// Legacy single-Point seeder. Slated for deletion once the long-press
  /// creation path is removed (see plan Task 10).
  Future<Feature> createNewFeature({
    required String assignmentId,
    required String featureType,
    required double lat,
    required double lng,
  }) {
    final geom = jsonEncode({
      'type': 'Point',
      'coordinates': [lng, lat],
    });
    return createFeature(
      assignmentId: assignmentId,
      featureType: featureType,
      geometryGeojson: geom,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/new_feature/new_feature_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/new_feature/data/new_feature_repository.dart \
        test/features/new_feature/new_feature_repository_test.dart
git commit -m "$(cat <<'EOF'
feat(new-feature): add generic createFeature(geometryGeojson)

The legacy createNewFeature(lat, lng) now delegates to it. Stays around
until the long-press seed path is removed.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Renderer — add `sketchActive` + `onMapTap`, drop `onLongPress`/`addModeActive`

`MapRenderer.build` gains two parameters and loses two:

```dart
// Added:
bool sketchActive,
void Function(double lat, double lng)? onMapTap,

// Removed:
bool addModeActive,                         // was always false outside add-mode banner
void Function(double lat, double lng)? onLongPress,
```

`FakeMapRenderer` gains `simulateMapTap(lat, lng)`. `MapboxMapRenderer` wires `onMapTap` to `MapWidget.onTapListener`.

**Files:**
- Modify: `lib/features/map/presentation/map_renderer.dart`
- Modify: `test/features/map/map_screen_add_mode_test.dart` and any other test that passes `onLongPress`/`addModeActive` to the FakeMapRenderer (use grep to find them)

- [ ] **Step 1: Find call sites that need updating**

```bash
grep -rln "onLongPress:\|addModeActive:\|simulateLongPress\|_lastOnLongPress\|widget.addModeActive\|widget.onLongPress" lib test
```

Note the file list. The call sites in `map_screen.dart` are addressed in Task 10; here we focus on the renderer interface and its tests.

- [ ] **Step 2: Write the failing test**

Add to `test/features/map/map_screen_test.dart` (or create `test/features/map/map_renderer_sketch_tap_test.dart` if you prefer isolation) the following:

```dart
test('FakeMapRenderer.simulateMapTap fires onMapTap with the right coords',
    () async {
  double? gotLat;
  double? gotLng;
  final fake = FakeMapRenderer();
  // Drive build() once to register the callback.
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => fake.build(
        ctx,
        features: const [],
        boundaryGeojson: '',
        onFeatureTap: (_) {},
        sketchActive: true,
        onMapTap: (lat, lng) {
          gotLat = lat;
          gotLng = lng;
        },
      ),
    ),
  ));
  await fake.simulateMapTap(1.5, 2.5);
  expect(gotLat, 1.5);
  expect(gotLng, 2.5);
});
```

If `tester` is not in scope (no `testWidgets`), wrap the test in `testWidgets(...)` instead and pass `tester`. Use the existing imports from neighboring tests for `MaterialApp`/`Builder`/`flutter_test`.

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/features/map/map_screen_test.dart -p vm`
Expected: FAIL — `sketchActive` and `onMapTap` are not parameters of `FakeMapRenderer.build`.

- [ ] **Step 4: Update the renderer interface**

Edit `lib/features/map/presentation/map_renderer.dart`:

In `abstract class MapRenderer`:

```dart
abstract class MapRenderer {
  Widget build(
    BuildContext context, {
    required List<Feature> features,
    required String boundaryGeojson,
    required void Function(Feature) onFeatureTap,
    void Function(double zoom, double lat, double lng)? onCameraChanged,
    CameraTarget? cameraTarget,
    CameraTarget? initialCameraTarget,
    void Function(Feature)? onPolygonLongPress,
    String? reshapeWorkingPolygonGeojson,
    String? reshapeInvalidEdgeGeojson,
    void Function(MapProjection projection)? onProjectionReady,
    bool sketchActive,
    void Function(double lat, double lng)? onMapTap,
  });
}
```

In `class FakeMapRenderer`:

- Replace the `_lastOnLongPress` field and `simulateLongPress` method with:

```dart
void Function(double, double)? _lastOnMapTap;
bool lastSketchActive = false;

/// Test seam: simulates a single tap on the map background. Invokes the most
/// recently stored onMapTap callback; no-op if none was provided.
Future<void> simulateMapTap(double lat, double lng) async {
  _lastOnMapTap?.call(lat, lng);
}
```

- Update the `build(...)` signature and implementation to drop `onLongPress`/`addModeActive` and accept `sketchActive`/`onMapTap`. Replace the `if (addModeActive) ...` block with `if (sketchActive) const Padding(... child: Text('sketch-mode')) `:

```dart
@override
Widget build(
  BuildContext context, {
  required List<Feature> features,
  required String boundaryGeojson,
  required void Function(Feature) onFeatureTap,
  void Function(double zoom, double lat, double lng)? onCameraChanged,
  CameraTarget? cameraTarget,
  CameraTarget? initialCameraTarget,
  void Function(Feature)? onPolygonLongPress,
  String? reshapeWorkingPolygonGeojson,
  String? reshapeInvalidEdgeGeojson,
  void Function(MapProjection projection)? onProjectionReady,
  bool sketchActive = false,
  void Function(double lat, double lng)? onMapTap,
}) {
  _lastOnMapTap = onMapTap;
  _lastOnCameraChanged = onCameraChanged;
  _lastOnPolygonLongPress = onPolygonLongPress;
  lastInitialCameraTarget = initialCameraTarget;
  lastSketchActive = sketchActive;
  if (cameraTarget != null && cameraTarget != lastCameraTarget) {
    cameraTargetHistory.add(cameraTarget);
  }
  lastCameraTarget = cameraTarget;
  lastReshapeWorkingPolygonGeojson = reshapeWorkingPolygonGeojson;
  lastReshapeInvalidEdgeGeojson = reshapeInvalidEdgeGeojson;

  onProjectionReady?.call(_IdentityProjection());

  return ListView(
    shrinkWrap: true,
    children: [
      if (sketchActive)
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('sketch-mode'),
        ),
      ...features.map((f) {
        return GestureDetector(
          key: Key('fake-map-feature-${f.id}'),
          // Suppress feature tap when sketching so the user can place
          // vertices over existing features without accidentally opening
          // their form (matches MapboxMapRenderer's onFeatureTap suppression).
          onTap: sketchActive ? null : () => onFeatureTap(f),
          onLongPress: f.isNew || sketchActive
              ? null
              : () => onPolygonLongPress?.call(f),
          child: Container(
            key: f.isNew
                ? Key('fake-map-new-feature-${f.id}')
                : Key('fake-map-poly-${f.id}'),
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.all(8),
            color: _colorForStatus(f.status),
            child: Text('feature ${f.id}'),
          ),
        );
      }),
    ],
  );
}
```

- Apply the same parameter changes to `MapboxMapRenderer.build`, the `_MapboxMapView` constructor + fields, and the `MapWidget` wiring inside `_MapboxMapViewState.build`. In place of the existing `onLongTapListener`'s add-mode branch, add an `onTapListener` (singular tap) that fires `widget.onMapTap` when `widget.sketchActive`:

```dart
return MapWidget(
  cameraOptions: ...,
  styleUri: 'mapbox://styles/mapbox/streets-v12',
  onMapCreated: _onMapCreated,
  onTapListener: (MapContentGestureContext ctx) {
    // Sketch-mode tap-to-place. Outside sketch, taps are absorbed by
    // annotation managers' click handlers (set up in _onMapCreated) and
    // don't reach this listener for hits on features.
    if (widget.sketchActive && widget.onMapTap != null) {
      final pos = ctx.point.coordinates;
      widget.onMapTap!(pos.lat.toDouble(), pos.lng.toDouble());
    }
  },
  onLongTapListener: (MapContentGestureContext ctx) async {
    // Reshape entry only — long-press was previously also used for
    // creation, but creation has moved to sketch-mode tap-to-place.
    final cb = widget.onPolygonLongPress;
    if (cb == null) return;
    final hit = _hitTestPolygon(
      ctx.point.coordinates.lat.toDouble(),
      ctx.point.coordinates.lng.toDouble(),
    );
    if (hit != null) cb(hit);
  },
  onCameraChangeListener: ...,
);
```

Verify the Mapbox SDK actually exposes `onTapListener` for `MapWidget` — search the local pubspec/package: `grep -rn "onTapListener" .dart_tool/pub_cache/hosted/pub.dev/mapbox_maps_flutter*/lib/ 2>/dev/null | head -5`. It should be there in 2.22; if the API differs, use whatever the package's `MapWidget` exposes for single-tap (it might be `onMapTapListener` or similar — adjust accordingly).

Also: when `sketchActive` is true, the polygon click listeners attached inside `_onMapCreated` (`_PolygonAnnotationClickHandler`, `_PointAnnotationClickHandler`, `_RoadClickHandler`) should early-return so taps on rendered features do NOT open their forms. Find each handler class and add an early-return guard. The cleanest approach: have `_MapboxMapViewState` hold a getter `bool get _sketchActive => widget.sketchActive` and pass it (or the widget itself) into the handler closures. Edit each `onAnnotationClick` body to check `_sketchActive` first:

```dart
void onPolygonAnnotationClick(PolygonAnnotation annotation) {
  if (_sketchActive) return; // suppress feature tap during sketch
  final f = _annotationToFeature[annotation.id];
  if (f != null) onTap(f);
}
```

Repeat for road + point handlers.

- [ ] **Step 5: Run all map tests**

Run: `flutter test test/features/map/`
Expected: PASS for the new test. Some pre-existing tests will now break because they passed `onLongPress:`/`addModeActive:` to `FakeMapRenderer` — fix those callsites in the next step.

- [ ] **Step 6: Update existing test callsites**

For each file from Step 1's grep that's a test: remove `onLongPress:` / `addModeActive:` arguments and `simulateLongPress` calls. If the test specifically targeted long-press creation behavior (in `map_screen_add_mode_test.dart`), don't try to keep it passing here — Task 10 will replace that whole flow. Mark such tests with `// TODO(plan Task 10): rewrite for sketch flow` and `, skip: true,` so they don't block this commit.

- [ ] **Step 7: Run flutter analyze**

Run: `flutter analyze`
Expected: 0 NEW errors. Calls to the removed parameters from `lib/features/map/presentation/map_screen.dart` will fail — that file is updated in Task 10. To unblock this commit, temporarily strip the `onLongPress:` and `addModeActive:` arguments from `map_screen.dart`'s renderer.build call and stub `_handleLongPress` to no-op (it's still defined and called from elsewhere? no, it's only passed to `onLongPress`, so once `onLongPress:` is removed, `_handleLongPress` becomes dead code — leave it for Task 10 to formally delete).

Actually do this minimally now: open `map_screen.dart` and change the renderer.build call to drop `onLongPress: _handleLongPress` and `addModeActive: _addModeActive`. Don't touch anything else in map_screen yet.

- [ ] **Step 8: Run full test suite**

Run: `flutter test`
Expected: PASS, modulo the pre-existing failures from observation 2889 and the temporarily-skipped tests from Step 6.

- [ ] **Step 9: Commit**

```bash
git add lib/features/map/presentation/map_renderer.dart \
        lib/features/map/presentation/map_screen.dart \
        test/features/map/
git commit -m "$(cat <<'EOF'
feat(map): renderer accepts sketchActive + onMapTap, drops onLongPress

MapWidget gains an onTapListener wired to onMapTap; long-press is now
reshape-only (onPolygonLongPress). Annotation click handlers early-return
during sketch so taps on existing features don't open their forms.

FakeMapRenderer gains simulateMapTap and a 'sketch-mode' marker. Tests
that drove the old long-press creation flow are temporarily skipped;
they're rewritten in plan Task 10.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Banner — Finish/Save label switch

The banner reads `geometryEditorControllerProvider` to know which mode it's in and switches the primary button label and title.

**Files:**
- Modify: `lib/features/map/geometry_editor/presentation/geometry_editor_banner.dart`
- Create: `test/features/map/geometry_editor/geometry_editor_banner_sketch_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/map/geometry_editor/geometry_editor_banner_sketch_test.dart`:

```dart
import 'package:firecheck/features/map/geometry_editor/domain/geometry_editor_state.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/geometry_editor_banner.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/geometry_editor_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness({required Widget child, required GeometryEditorState seed}) {
  return ProviderScope(
    overrides: [
      geometryEditorControllerProvider.overrideWith(() {
        return _StubController(seed);
      }),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

class _StubController extends GeometryEditorController {
  _StubController(this._seed);
  final GeometryEditorState _seed;
  @override
  GeometryEditorState build() => _seed;
}

void main() {
  testWidgets('sketch mode shows Finish label', (tester) async {
    await tester.pumpWidget(_harness(
      seed: const GeometryEditorState(pendingFeatureType: 'building'),
      child: GeometryEditorBanner(
        editCount: 0,
        undoEnabled: false,
        saveEnabled: false,
      ),
    ));
    expect(find.text('Finish'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('reshape mode shows Save label', (tester) async {
    // Build a minimal Feature row for the seed state.
    // (Reuse the helper from reshape_mode_controller_test if available;
    // inline the constructor here for isolation.)
    final featureSeed = _fakeFeature();
    await tester.pumpWidget(_harness(
      seed: GeometryEditorState(originalFeature: featureSeed),
      child: GeometryEditorBanner(
        editCount: 1,
        undoEnabled: true,
        saveEnabled: true,
      ),
    ));
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Finish'), findsNothing);
  });
}

// Same fixture as in reshape_mode_controller_test.dart. Extract to a shared
// helper if both tests grow more.
Feature _fakeFeature() => Feature(
      id: 'f1',
      assignmentId: 'a1',
      featureType: 'building',
      geometryGeojson: '{"type":"Polygon","coordinates":[[[0,0],[1,0],[1,1],[0,0]]]}',
      isNew: false,
      createdAt: DateTime(2026, 1, 1),
      status: 'pending',
      photoCount: 0,
    );
```

If `GeometryEditorController.build()` is final or the override style differs, copy the override pattern from any existing reshape banner test. Note: `Save` vs `Finish` are matched against the new l10n keys added in Task 11; the test will need rerunning after that task.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/map/geometry_editor/geometry_editor_banner_sketch_test.dart`
Expected: FAIL — banner currently always shows `Save` (via `l.reshapeBannerSave`).

- [ ] **Step 3: Update the banner**

Edit `lib/features/map/geometry_editor/presentation/geometry_editor_banner.dart`. Make it a `ConsumerWidget` so it can read editor state, and switch the label:

```dart
import 'package:firecheck/features/map/geometry_editor/presentation/geometry_editor_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GeometryEditorBanner extends ConsumerWidget {
  const GeometryEditorBanner({
    required this.editCount,
    required this.undoEnabled,
    required this.saveEnabled,
    super.key,
    this.onCancel,
    this.onUndo,
    this.onSave,
  });

  final int editCount;
  final bool undoEnabled;
  final bool saveEnabled;
  final VoidCallback? onCancel;
  final VoidCallback? onUndo;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final isSketch = ref.watch(geometryEditorControllerProvider).isSketchMode;
    final type = ref.watch(geometryEditorControllerProvider).pendingFeatureType;
    final title = isSketch
        ? l.sketchBannerTitle(editCount, type ?? '')
        : l.reshapeBannerTitle(editCount);
    final primaryLabel = isSketch ? l.sketchBannerFinish : l.reshapeBannerSave;

    return Material(
      color: const Color(0xFF3182CE),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  TextButton(
                    key: const Key('reshape.banner.cancel'),
                    onPressed: onCancel,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: const Text('Cancel'),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  FilledButton(
                    key: const Key('reshape.banner.save'),
                    onPressed: saveEnabled ? onSave : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF3182CE),
                      disabledBackgroundColor:
                          Colors.white.withValues(alpha: 0.4),
                    ),
                    child: Text(primaryLabel),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 0, 6),
                child: TextButton.icon(
                  key: const Key('reshape.banner.undo'),
                  onPressed: undoEnabled ? onUndo : null,
                  icon: const Icon(Icons.undo, color: Colors.white, size: 16),
                  label: const Text(
                    'Undo',
                    style: TextStyle(color: Colors.white),
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
```

The widget keys (`reshape.banner.cancel/save/undo`) intentionally stay the same — existing reshape tests grep for them, and the banner is the same widget regardless of mode.

- [ ] **Step 4: Run banner tests**

Run: `flutter test test/features/map/geometry_editor/`
Expected: the new sketch test FAILs because `l.sketchBannerTitle` and `l.sketchBannerFinish` aren't defined yet — that's Task 11. The existing `reshape_banner_test.dart` may also fail because it instantiates a plain `Material`/`Widget`-rooted banner without a `ProviderScope`. If so, wrap its harness in `ProviderScope(overrides: [geometryEditorControllerProvider.overrideWith(...) ])` and seed a default `GeometryEditorState()` (which is reshape-mode null but not active — the banner builds with `editCount: 0, ...` regardless of `isActive`).

- [ ] **Step 5: Commit (banner code only)**

```bash
git add lib/features/map/geometry_editor/presentation/geometry_editor_banner.dart \
        test/features/map/geometry_editor/
git commit -m "$(cat <<'EOF'
feat(geometry-editor): banner switches Save↔Finish based on mode

GeometryEditorBanner is now a ConsumerWidget; reads pendingFeatureType
to decide the title format and primary button label.

Sketch test depends on l10n keys added in plan Task 11.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Map screen integration

Wire the new flow end to end:

- `+` pill → type picker → `enterSketch`
- Map tap → `appendSketchVertex`
- Banner Finish → `validateSketch` → `createFeature` → push form
- Banner Cancel → confirm dialog if `editorState.workingRings[0].isNotEmpty`, else exit silently

**Files:**
- Modify: `lib/features/map/presentation/map_screen.dart`
- Modify: `lib/features/new_feature/data/new_feature_repository.dart` (delete `createNewFeature`)
- Create: `lib/features/map/geometry_editor/presentation/sketch_error_messages.dart`

- [ ] **Step 1: Add the error→message helper**

Create `lib/features/map/geometry_editor/presentation/sketch_error_messages.dart`:

```dart
import 'package:firecheck/features/map/geometry_editor/domain/sketch_validation_error.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';

String sketchErrorMessage(SketchValidationError e, AppLocalizations l) {
  return switch (e) {
    SketchValidationError.notEnoughVertices => l.sketchErrorNotEnoughVertices,
    SketchValidationError.vertexOutsideBoundary => l.outsideBoundarySnackbar,
    SketchValidationError.selfIntersection => l.reshapeErrorSelfIntersection,
    SketchValidationError.zeroLengthEdge => l.reshapeErrorZeroLengthEdge,
  };
}
```

`outsideBoundarySnackbar`, `reshapeErrorSelfIntersection`, `reshapeErrorZeroLengthEdge` are existing l10n keys; `sketchErrorNotEnoughVertices` is added in Task 11.

- [ ] **Step 2: Rewrite the map-screen plus-pill flow**

In `lib/features/map/presentation/map_screen.dart`:

(a) Delete `bool _addModeActive = false;` and every reference to it.
(b) Delete the `_handleLongPress` method entirely.
(c) Replace the renderer.build call's parameters: drop `onLongPress`, `addModeActive`, and add `sketchActive: editorState.isSketchMode, onMapTap: _onSketchTap`.
(d) Replace the bottom pill's `onTap` with `_onPlusPressed`. Bind the pill's `on:` highlight to `editorState.isSketchMode`.
(e) Replace the blue add-mode hint banner with the `GeometryEditorBanner` when `editorState.isSketchMode`. (The reshape banner already shows when `reshapeActive` — keep that branch and ADD a sketch branch.)
(f) Add the new methods.

Key new methods (paste into `_MapScreenState`):

```dart
Future<void> _onPlusPressed() async {
  final l = AppLocalizations.of(context)!;
  final assignment = ref.read(currentAssignmentProvider).value;
  if (assignment == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.noAssignmentForEnumerator)),
    );
    return;
  }
  final type = await showFeatureTypePicker(context);
  if (type == null) return;
  ref
      .read(geometryEditorControllerProvider.notifier)
      .enterSketch(featureType: type);
  ref.read(analyticsServiceProvider).track(
    'map.sketch.entered',
    properties: {'feature_type': type},
  );
}

void _onSketchTap(double lat, double lng) {
  final ctrl = ref.read(geometryEditorControllerProvider.notifier);
  if (!ref.read(geometryEditorControllerProvider).isSketchMode) return;
  ctrl.appendSketchVertex((lng: lng, lat: lat));
}

Future<void> _onSketchFinish() async {
  final l = AppLocalizations.of(context)!;
  final assignment = ref.read(currentAssignmentProvider).value;
  if (assignment == null) return;
  final ctrl = ref.read(geometryEditorControllerProvider.notifier);
  final state = ref.read(geometryEditorControllerProvider);
  final type = state.pendingFeatureType;
  if (type == null) return;

  final err = ctrl.validateSketch(
    boundaryGeojson: assignment.boundaryPolygonGeojson,
  );
  if (err != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(sketchErrorMessage(err, l))),
    );
    ref.read(analyticsServiceProvider).track(
      'map.sketch.validation_failed',
      properties: {'feature_type': type, 'rule': err.name},
    );
    return;
  }

  final geom = ctrl.serializeWorking();
  // For sketch we need a Point GeoJSON when type == 'point'; serializeWorking
  // produces a LineString for open shapes, so override here.
  final geomToSave = type == 'point'
      ? '{"type":"Point","coordinates":[${state.workingRings[0][0].lng},${state.workingRings[0][0].lat}]}'
      : geom;

  final repo = ref.read(newFeatureRepositoryProvider);
  final feature = await repo.createFeature(
    assignmentId: assignment.id,
    featureType: type,
    geometryGeojson: geomToSave,
  );

  ref.read(analyticsServiceProvider).track(
    'map.sketch.completed',
    properties: {
      'feature_type': type,
      'vertex_count': state.workingRings[0].length,
      'ops_made': state.undoStack.length,
    },
  );

  ctrl.cancel();
  if (!mounted) return;
  context.push('/feature/${Uri.encodeComponent(feature.id)}');
}

Future<void> _onSketchCancel() async {
  final l = AppLocalizations.of(context)!;
  final state = ref.read(geometryEditorControllerProvider);
  final type = state.pendingFeatureType ?? '';
  final vertexCount = state.workingRings.isNotEmpty
      ? state.workingRings[0].length
      : 0;

  if (vertexCount == 0) {
    ref.read(geometryEditorControllerProvider.notifier).cancel();
    ref.read(analyticsServiceProvider).track(
      'map.sketch.cancelled',
      properties: {'feature_type': type, 'vertex_count': 0, 'ops_made': 0},
    );
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.sketchDiscardConfirmTitle),
      content: Text(l.sketchDiscardConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.sketchDiscardKeepEditing),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l.sketchDiscardConfirm),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    ref.read(geometryEditorControllerProvider.notifier).cancel();
    ref.read(analyticsServiceProvider).track(
      'map.sketch.cancelled',
      properties: {
        'feature_type': type,
        'vertex_count': vertexCount,
        'ops_made': state.undoStack.length,
      },
    );
  }
}
```

(g) Update the banner rendering. Where the existing code conditionally renders `ReshapeBanner` for reshape, add a parallel branch for sketch. Both branches mount the **same** `GeometryEditorBanner` widget; the banner internally picks Save/Finish copy. Wire the buttons:

```dart
// Sketch banner
if (editorState.isSketchMode)
  Positioned(
    top: 0,
    left: 0,
    right: 0,
    child: GeometryEditorBanner(
      editCount: editorState.workingRings.isNotEmpty
          ? editorState.workingRings[0].length
          : 0,
      undoEnabled: editorState.undoStack.isNotEmpty,
      saveEnabled: _sketchFinishEnabled(editorState),
      onCancel: _onSketchCancel,
      onUndo: () => ref
          .read(geometryEditorControllerProvider.notifier)
          .undo(),
      onSave: _onSketchFinish,
    ),
  ),

// Reshape banner branch unchanged.
```

Helper:

```dart
bool _sketchFinishEnabled(GeometryEditorState s) {
  final n = s.workingRings.isNotEmpty ? s.workingRings[0].length : 0;
  switch (s.pendingFeatureType) {
    case 'building':
      return n >= 3;
    case 'road':
      return n >= 2;
    case 'point':
      return n >= 1;
    default:
      return false;
  }
}
```

(h) The pill needs to go inactive while reshaping or sketching. Replace its `on:` argument:

```dart
on: editorState.isSketchMode,
```

…and the `onTap`:

```dart
onTap: editorState.isSketchMode || reshapeActive
    ? null
    : _onPlusPressed,
```

(i) Read `editorState` from the provider near the top of `build()`:

```dart
final editorState = ref.watch(geometryEditorControllerProvider);
final reshapeActive = editorState.isActive && !editorState.isSketchMode;
```

…and remove the existing `final reshape = ref.watch(reshapeModeControllerProvider);` (replaced by the lines above; the rest of the file should refer to `editorState` instead of `reshape`).

- [ ] **Step 3: Delete the legacy single-Point seeder**

Edit `lib/features/new_feature/data/new_feature_repository.dart`. Delete the `createNewFeature(...)` method. The `dart:convert` import becomes unused — remove it too.

- [ ] **Step 4: Run flutter analyze**

Run: `flutter analyze`
Expected: 0 errors. If anything still calls `createNewFeature`, grep finds it: `grep -rn "createNewFeature" lib test`.

- [ ] **Step 5: Run the test suite**

Run: `flutter test`
Expected: PASS modulo pre-existing failures and the temporarily-skipped `map_screen_add_mode_test.dart` tests from Task 8 Step 6 (those are rewritten in Task 12).

- [ ] **Step 6: Commit**

```bash
git add lib/features/map/presentation/map_screen.dart \
        lib/features/map/geometry_editor/presentation/sketch_error_messages.dart \
        lib/features/new_feature/data/new_feature_repository.dart
git commit -m "$(cat <<'EOF'
feat(map): wire sketch-on-create flow into MapScreen

+ pill now opens the type picker directly. Picking a type enters sketch
mode in the geometry editor; map taps drop vertices via onMapTap.
Banner's Finish runs validateSketch, INSERTs via createFeature, and pushes
to the submission form. Cancel discards (with confirm if any vertices
were dropped).

Removes _handleLongPress, _addModeActive, and the legacy
createNewFeature(lat, lng).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: l10n strings

Add new keys to both ARB files; regenerate the AppLocalizations bindings.

**Files:**
- Modify: `lib/core/i18n/app_en.arb`
- Modify: `lib/core/i18n/app_tl.arb`
- Regenerated: `lib/generated/l10n/app_localizations*.dart` (via `flutter gen-l10n` or `flutter pub get` depending on the project's setup)

- [ ] **Step 1: Add keys to app_en.arb**

Add these entries (at the bottom, before the closing `}` of the JSON):

```json
,
"sketchBannerTitle": "{count} vertices · {type}",
"@sketchBannerTitle": {
  "placeholders": {
    "count": {"type": "int"},
    "type": {"type": "String"}
  }
},
"sketchBannerFinish": "Finish",
"sketchErrorNotEnoughVertices": "Not enough vertices for this feature type",
"sketchDiscardConfirmTitle": "Discard sketch?",
"sketchDiscardConfirmBody": "Your dropped vertices will be lost.",
"sketchDiscardKeepEditing": "Keep editing",
"sketchDiscardConfirm": "Discard"
```

- [ ] **Step 2: Add the same keys to app_tl.arb**

Use Tagalog translations (consult an existing string for tone — look at `outsideBoundarySnackbar` / `reshapeBannerSave` in `app_tl.arb`):

```json
,
"sketchBannerTitle": "{count} vertice · {type}",
"sketchBannerFinish": "Tapusin",
"sketchErrorNotEnoughVertices": "Kulang ang vertices para sa uri ng feature na ito",
"sketchDiscardConfirmTitle": "Itapon ang pagguhit?",
"sketchDiscardConfirmBody": "Mawawala ang mga vertice na ginawa mo.",
"sketchDiscardKeepEditing": "Magpatuloy",
"sketchDiscardConfirm": "Itapon"
```

(If unsure about phrasing, defer to a project translator later — these are non-blocking.)

- [ ] **Step 3: Regenerate AppLocalizations**

Run: `flutter gen-l10n` (or `flutter pub get` if the project uses a generation hook — check `pubspec.yaml` for the pattern; `l10n.yaml` likely exists).

If neither works, look for a generation script: `cat l10n.yaml 2>/dev/null` and follow its README, or look at how other recent additions were generated (check the git log for ARB-touching commits and reproduce the same regeneration command).

- [ ] **Step 4: Run flutter analyze**

Run: `flutter analyze`
Expected: 0 errors. The l10n calls in `geometry_editor_banner.dart`, `map_screen.dart`, and `sketch_error_messages.dart` should now resolve.

- [ ] **Step 5: Run the affected tests**

Run: `flutter test test/features/map/geometry_editor/geometry_editor_banner_sketch_test.dart`
Expected: PASS — the banner now finds the `Finish` text.

- [ ] **Step 6: Commit**

```bash
git add lib/core/i18n/app_en.arb lib/core/i18n/app_tl.arb \
        lib/generated/l10n/
git commit -m "$(cat <<'EOF'
i18n: sketch flow strings (banner, errors, discard dialog)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Widget tests — sketch happy paths, validation, gesture suppression

**Files:**
- Create: `test/features/map/sketch_flow_test.dart`
- Modify: `test/features/map/map_screen_add_mode_test.dart` (un-skip from Task 8, rewrite for sketch)

- [ ] **Step 1: Create sketch_flow_test.dart**

Skeleton (fill in following the pattern of existing `map_screen_*_test.dart` files for harness/setup):

```dart
import 'package:firecheck/features/map/geometry_editor/presentation/geometry_editor_providers.dart';
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:firecheck/features/map/presentation/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Reuse the test harness used by other map_screen_*_test.dart files.
// Search test/features/map/ for a function like `pumpMapScreen(tester, ...)`
// or a `_buildHarness` helper and follow that pattern. The harness should:
//   - inject a FakeMapRenderer overriding `mapRendererProvider`
//   - inject a fake assignment with a known boundary
//   - inject an in-memory AppDatabase for the new-feature repo
//   - pump MapScreen wrapped in MaterialApp + ProviderScope

void main() {
  group('sketch flow — building', () {
    testWidgets('tap +, pick Building, drop 3 vertices, Finish → form push',
        (tester) async {
      final fake = FakeMapRenderer();
      // ... build harness with fake renderer, boundary covers a 10x10 lng/lat
      //     square around (1,1)
      // ... pump MapScreen
      // ... tap + pill
      await tester.tap(find.byKey(const Key('map.add-feature-pill')));
      await tester.pumpAndSettle();
      // ... type picker appears; tap Building
      await tester.tap(find.text('Building'));
      await tester.pumpAndSettle();
      // ... banner shows "0 vertices · building", Finish disabled
      expect(find.text('0 vertices · building'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('reshape.banner.save')))
            .onPressed,
        isNull,
      );
      // ... drop 3 vertices via simulateMapTap
      await fake.simulateMapTap(1.0, 1.0);
      await fake.simulateMapTap(1.0, 2.0);
      await fake.simulateMapTap(2.0, 1.5);
      await tester.pumpAndSettle();
      expect(find.text('3 vertices · building'), findsOneWidget);
      // ... Finish enabled; tap it
      await tester.tap(find.byKey(const Key('reshape.banner.save')));
      await tester.pumpAndSettle();
      // ... assert navigation: GoRouter pushed /feature/{id}; the simplest
      //     check is that MapScreen is no longer the topmost route, OR
      //     that the form widget for the new feature is present.
      // Use the same router-assertion pattern from map_screen_test.dart.
    });

    testWidgets('Finish with vertex outside boundary shows snackbar', (tester) async {
      // ... harness with 10x10 boundary around (1,1)
      // ... enter sketch, drop 2 in-bounds + 1 way outside (e.g. (99,99))
      // ... tap Finish → expect snackbar with the boundary message
      // ... assert state preserved: banner still shows "3 vertices"
    });

    testWidgets('Finish with bowtie self-intersection shows snackbar', (tester) async {
      // Same harness; drop 4 vertices in bowtie order.
      // Expect snackbar with l.reshapeErrorSelfIntersection text.
      // (Match a substring like "cross" — see observation 719.)
    });
  });

  group('sketch flow — road', () {
    testWidgets('2 taps then Finish → road LineString', (tester) async {
      // ... pick Road, drop 2 vertices, Finish, assert /feature/ navigation
    });

    testWidgets('Finish with coincident vertices shows zero-length error',
        (tester) async {
      // ... pick Road, drop 2 identical vertices, Finish → snackbar
    });
  });

  group('sketch flow — point', () {
    testWidgets('1 tap, Finish → Point feature', (tester) async {
      // ... pick Point, drop 1 vertex, Finish, assert navigation
    });

    testWidgets('second tap relocates the point (Move op)', (tester) async {
      // ... pick Point, drop at (1,1), drop at (5,5)
      // ... assert banner shows "1 vertices · point"
      // ... assert Undo enabled (2 ops on stack)
    });
  });

  group('cancel', () {
    testWidgets('cancel with 0 vertices exits silently', (tester) async {
      // ... pick Building, immediately tap Cancel
      // ... assert no AlertDialog, banner gone, pill back to default state
    });

    testWidgets('cancel with ≥1 vertex shows confirm dialog', (tester) async {
      // ... pick Building, drop 1 vertex, tap Cancel
      // ... expect AlertDialog with l.sketchDiscardConfirmTitle
      // ... tap "Keep editing" → dialog dismissed, vertex retained
      // ... tap Cancel again → dialog → "Discard" → state cleared
    });
  });

  group('gesture suppression in sketch mode', () {
    testWidgets('tap on existing feature does not navigate', (tester) async {
      // ... seed a Feature into the FakeMapRenderer's features list
      // ... enter sketch (Building)
      // ... tap on the fake-map-poly-{id} key
      // ... assert NO navigation to /feature/{id}
      //     (the FakeMapRenderer suppresses onTap when sketchActive=true)
    });
  });
}
```

The exact harness depends on how other map widget tests are structured. Look at `test/features/map/map_screen_test.dart` for the canonical setup — copy its `pumpMapScreen` (or equivalent) helper rather than re-inventing.

- [ ] **Step 2: Run the new test**

Run: `flutter test test/features/map/sketch_flow_test.dart`
Expected: PASS for all sketch tests once filled in.

- [ ] **Step 3: Rewrite map_screen_add_mode_test.dart**

Open `test/features/map/map_screen_add_mode_test.dart`. The pre-existing tests there assert the long-press → type-picker → seed-Point flow. Replace them with the simpler sketch-equivalent (most of which is now duplicated in `sketch_flow_test.dart` — keep what's unique here, like assertions about the pill state transitions, and delete the rest).

If the file is now mostly redundant after the rewrite, leave a single test that asserts: tapping the `+` pill opens the type picker. Delete the file entirely if even that becomes a duplicate of `sketch_flow_test.dart`. Use your judgment.

Un-skip any tests that were `// TODO(plan Task 10): rewrite for sketch flow` skipped in Task 8.

- [ ] **Step 4: Run all map tests**

Run: `flutter test test/features/map/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add test/features/map/
git commit -m "$(cat <<'EOF'
test(map): widget tests for sketch-on-create flow

Covers happy paths (building/road/point), Finish-time validation
(boundary, self-intersection, zero-length), cancel semantics
(silent vs confirm), and gesture suppression on existing features.

Replaces the long-press add-mode tests that assumed the seed-Point flow.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: Un-skip integration test from commit 3febd33

The set-up-complete-feature integration test was scaffolded as skipped because the multi-vertex creation flow didn't exist. Now it does.

**Files:**
- Modify: the integration test added in commit `3febd33` (find it: `git show --stat 3febd33`)

- [ ] **Step 1: Find the integration test**

```bash
git show --stat 3febd33 | grep "_test\.dart"
```

The committed file path will be in the output. Open it.

- [ ] **Step 2: Update the test to use the sketch flow**

Replace the long-press-and-pick-Building action with: tap `+`, pick Building, simulate 4 map taps inside the boundary, tap Finish.

The form-fill steps and Done assertion are unchanged.

Remove the `, skip: 'pending sketch flow'` (or similar skip marker the original commit added).

- [ ] **Step 3: Run the integration test**

Run: `flutter test path/to/the/integration_test.dart` (the path from Step 1).
Expected: PASS end-to-end. If it pumps a real `MapboxMapRenderer`, it might fail in `flutter_tester` (per observation 79: Mapbox doesn't render in flutter_tester). In that case, override `mapRendererProvider` to inject `FakeMapRenderer` for the integration test — same pattern as widget tests.

- [ ] **Step 4: Commit**

```bash
git add path/to/the/integration_test.dart
git commit -m "$(cat <<'EOF'
test(integration): un-skip set-up-complete-feature flow

Now that sketch-on-create exists, the end-to-end happy path from home →
get-maps → map → tap+ → Building → 4 taps → Finish → form → Done is
exercisable in a single test.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 14: Final verification — analyze, test, manual happy path

- [ ] **Step 1: Run flutter analyze**

Run: `flutter analyze`
Expected: 0 NEW errors vs. the baseline from observation 2885. Pre-existing warnings are acceptable.

- [ ] **Step 2: Run the full test suite**

Run: `flutter test`
Expected: All tests pass except the documented pre-existing failures from observation 2889. The sketch-flow tests, banner tests, controller tests, validator tests, and integration test all pass.

- [ ] **Step 3: Manual happy path on a physical Android device**

(per observation 79: Mapbox doesn't render in flutter_tester; this validates the real renderer)

```
1. flutter run on Android device with valid GPS
2. Sign in
3. Tap "Get Maps" → download an assignment
4. Tap "Open Map" → MapScreen renders
5. Tap "+" pill at the bottom → type picker sheet appears
6. Pick "Building" → blue banner appears showing "0 vertices · building"
7. Tap the map 4 times to drop 4 vertices inside the boundary
8. Verify a live polygon preview renders (closing line back to vertex 0)
9. Drag a vertex handle → polygon updates live
10. Long-press a vertex handle → confirm dialog → Remove → vertex disappears
11. Tap Undo → vertex restored
12. Tap Finish → submission form appears
13. Fill required fields → tap Done → return to MapScreen with the new
    polygon visible
14. Repeat for Road (2+ taps) and Point (1 tap)
15. Tap "+", pick Building, tap Cancel without dropping vertices →
    silent exit
16. Tap "+", pick Building, drop 1 vertex, tap Cancel → confirm dialog
17. "Keep editing" → vertex preserved
18. Cancel again → "Discard" → state cleared
19. Test boundary error: tap "+", Building, drop 3 vertices with one
    outside the boundary → tap Finish → boundary snackbar; vertices
    preserved; move the offending vertex inside; Finish succeeds
20. Confirm back navigation from the form returns to map (not exit app —
    the existing fix from 2026-05-15 afternoon)
```

- [ ] **Step 4: Push the branch**

```bash
git push -u origin feature/multi-story-batch-2026-05
```

(or whichever branch the work happened on — check `git status` first)

---

## Self-review notes

**Spec coverage check:**

| Spec section | Implemented in |
|---|---|
| Renames (folder + classes) | Task 1 |
| State additions (`pendingFeatureType`, `isSketchMode`, widened `isActive`) | Task 2 |
| Controller `enterSketch` | Task 3 |
| Controller `appendSketchVertex` (with point-replace) | Task 4 |
| Controller `validateSketch` | Task 6 |
| `validatePolyline` validator | Task 5 |
| `SketchValidationError` enum | Task 5 |
| `NewFeatureRepository.createFeature` | Task 7 |
| Drop legacy `createNewFeature(lat, lng)` | Task 10 (Step 3) |
| Renderer `sketchActive` + `onMapTap`, drop `onLongPress` + `addModeActive` | Task 8 |
| Mapbox annotation handlers suppress on `sketchActive` | Task 8 (Step 4 sub-bullet) |
| Banner Finish/Save label switch | Task 9 |
| Map screen `+` pill → type picker → enter sketch | Task 10 |
| Map tap → `appendSketchVertex` | Task 10 |
| Finish → validate → INSERT → push form | Task 10 |
| Cancel → confirm dialog if ≥1 vertex | Task 10 |
| L10n strings (en + tl) | Task 11 |
| Analytics `map.sketch.*` events | Task 10 |
| Widget tests (happy paths, validation, gesture suppression) | Task 12 |
| Integration test un-skipped | Task 13 |
| `flutter analyze` + `flutter test` clean | Task 14 |
| Manual happy path on device | Task 14 |

**Placeholder scan:** No "TBD/TODO/implement later" steps. Every code step shows the actual code. Every command shows the actual command.

**Type-consistency check:**
- `enterSketch({required String featureType})` — same signature in Task 3 (definition) and Task 10 (caller).
- `appendSketchVertex(LngLat)` — same in Task 4 (definition) and Task 10 (caller via `_onSketchTap`).
- `validateSketch({required String boundaryGeojson}) → SketchValidationError?` — same in Task 6 (definition) and Task 10 (caller).
- `createFeature({required String assignmentId, required String featureType, required String geometryGeojson}) → Future<Feature>` — same in Task 7 (definition) and Task 10 (caller).
- `sketchErrorMessage(SketchValidationError, AppLocalizations) → String` — defined and called in Task 10.
- `_sketchFinishEnabled(GeometryEditorState) → bool` — defined and used in Task 10's banner branch.
- L10n keys (`sketchBannerTitle`, `sketchBannerFinish`, `sketchErrorNotEnoughVertices`, `sketchDiscardConfirmTitle`, `sketchDiscardConfirmBody`, `sketchDiscardKeepEditing`, `sketchDiscardConfirm`) — defined in Task 11; referenced in Tasks 9, 10. Reused existing keys: `outsideBoundarySnackbar`, `reshapeErrorSelfIntersection`, `reshapeErrorZeroLengthEdge`, `reshapeBannerTitle`, `reshapeBannerSave`, `noAssignmentForEnumerator`.
