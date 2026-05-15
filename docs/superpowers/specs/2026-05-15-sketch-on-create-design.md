# Sketch-on-create: multi-vertex feature creation

**Date:** 2026-05-15
**Status:** Draft — design approved, awaiting implementation plan
**Branch (likely):** `feature/sketch-on-create`

## Problem

Today, tapping the `+` pill on the map and long-pressing seeds a single-Point GeoJSON regardless of feature type. Building and Road features end up as dots in the database. The only way to give them real geometry is to save the seed Point, then enter Reshape mode on the resulting feature and add vertices via midpoint handles — an awkward two-stage workflow that no user discovers on their own.

`NewFeatureRepository.createNewFeature` (`lib/features/new_feature/data/new_feature_repository.dart:12`) hard-codes the `Point` GeoJSON. There is no tap-to-drop-vertex sketch flow anywhere in the codebase.

## Goal

Let the user sketch real polygons and polylines at creation time:

- Tap `+` → pick type → tap to drop vertices with a live preview → tap **Finish** → land in the submission form with a properly-shaped Building / Road / Point feature.
- Reuse the existing reshape system (drag handles, undo, projection overlay) rather than building a parallel sketch system.

## Non-goals

- Persisted drafts of in-progress sketches. Cancel discards.
- Live validation while sketching (boundary, self-intersection, etc.) — only on Finish.
- Holes/inner rings in polygons. Single ring only, matching today's reshape capabilities.
- Multi-part geometry. One ring / one linestring / one point per feature.

## User flow

1. User taps `+` pill on the map.
2. Type picker sheet appears immediately (currently fires after long-press).
3. User picks **Building** / **Road** / **Point**.
4. Editor mode activates: top banner shows `0 vertices • {type}` with **Undo**, **Cancel**, **Finish** buttons. Finish is disabled until the per-type minimum is met.
5. User taps the map to drop vertices. A live preview renders:
   - Building → polygon with closing line back to vertex 0
   - Road → open polyline
   - Point → single dot
6. User can refine while sketching:
   - **Tap a vertex handle** → remove that vertex
   - **Drag a vertex handle** → move it
   - **Drag a midpoint handle** → insert a new vertex between two existing ones (polygon/polyline only)
   - **Undo** → pop the last operation off the stack
7. Finish button enables once minimum vertices are met (3 / 2 / 1). For Point, additional taps replace vertex 0 instead of appending.
8. **Finish** runs validators (see below). On success the feature is INSERTed and the user is pushed to `/feature/{id}`. On failure a snackbar names the specific problem; vertices stay on screen.
9. **Cancel** with 0 vertices exits silently. With ≥1 vertex, a "Discard sketch?" confirm dialog appears; on confirm, all state is cleared.

## Architecture

The reshape system already implements ~90% of what sketching needs: a working ring of vertices, an undo stack of `Move` / `Add` / `Remove` / `Translate` ops, vertex/midpoint handles in a projected overlay, polygon vs polyline awareness via `isClosed`. We extend it into a unified geometry editor instead of building a parallel sketch system.

### Renames

Folder `lib/features/map/reshape/` → `lib/features/map/geometry_editor/`.

| Before | After |
|---|---|
| `ReshapeModeController` | `GeometryEditorController` |
| `ReshapeModeState` | `GeometryEditorState` |
| `reshapeModeControllerProvider` | `geometryEditorControllerProvider` |
| `ReshapeBanner` | `GeometryEditorBanner` |
| `ReshapeOverlay` | `GeometryEditorOverlay` |
| `ReshapeOp`, `Move`, `Add`, `Remove`, `Translate` | unchanged |

`reshapeRepositoryProvider` and `feature_geometry_revisions_repository.dart` keep their names — the revisions audit trail is reshape-specific (existing-feature edits) and does not apply to fresh creates.

### State additions

`GeometryEditorState` gains:

```dart
final String? pendingFeatureType;   // 'building' | 'road' | 'point' | null
bool get isSketchMode => originalFeature == null && pendingFeatureType != null;
bool get isActive => originalFeature != null || isSketchMode;  // widened
```

Existing fields (`workingRings`, `undoStack`, `isClosed`, `saving`, `selfIntersects`, `overrideReason`) are reused as-is. In sketch mode `workingRings` starts as `[[]]`; `isClosed` is set from the type (`building` → true, `road`/`point` → false).

### Controller additions

```dart
void enterSketch({required String featureType});
void appendVertex(LngLat p);   // for 'point', replaces vertex 0 if one exists
Future<Feature?> finishSketch();
void cancelSketch();
```

Existing `enterReshape`, `saveReshape`, `undo`, drag, remove paths are unchanged. The save flow branches once: when `originalFeature == null`, INSERT a new row via `NewFeatureRepository.createFeature(...)`; otherwise go through `reshapeRepository.saveReshape(...)` as today.

## Persistence

The database is untouched until validation passes on Finish. No drafts, no orphan rows. Cancelling leaves no trace.

`NewFeatureRepository` gains a generic creator alongside today's lat/lng one:

```dart
Future<Feature> createFeature({
  required String assignmentId,
  required String featureType,
  required String geometryGeojson,   // pre-built by the editor
});
```

The existing `createNewFeature(lat, lng)` and the `_handleLongPress` flow that calls it are deleted. Long-press is no longer a creation trigger anywhere; the `+` pill is the single entry point.

### GeoJSON serialization (built by `finishSketch` before validation)

| type | shape | rule |
|---|---|---|
| `building` | `Polygon` | close ring (append `coords[0]` if not already equal); `validateBuildingPolygon` already auto-fixes orientation |
| `road` | `LineString` | use `workingRings[0]` as-is |
| `point` | `Point` | `coordinates: workingRings[0][0]` |

## Validation (run in `finishSketch`, before INSERT)

In order; first failure short-circuits with a snackbar and preserves editor state.

1. **Min vertex count** — 3 for `building`, 2 for `road`, 1 for `point`. Below threshold → `"Need at least N vertices"`.
2. **Per-vertex boundary** — every vertex must satisfy `pointInPolygonGeojson(lat, lng, assignment.boundaryPolygonGeojson)`. If the boundary is empty/invalid (per the `polygonBoundsFromGeojson` fallback added 2026-05-15 morning), skip this check. First out-of-boundary vertex → `"Vertex N is outside your assignment area"`.
3. **Polygon-only** — for `building`, run existing `validateBuildingPolygon` (closure, orientation auto-fix, self-intersection, zero-length edges). Reuse the existing `_validationMessage` switch from `map_screen.dart:355`.
4. **Polyline-only** — for `road`, ensure no two adjacent vertices are coincident. New tiny `validatePolyline(parts)` validator in `core/geo/`.
5. **Point** — only the boundary check applies.

## Map screen integration

- Drop the local `_addModeActive` bool. The pill's "active" highlight binds to `editorState.isSketchMode`.
- Replace `_handleLongPress` with `_onPlusPressed()` — shows the existing `showFeatureTypePicker` sheet immediately, then calls `controller.enterSketch(...)` on selection.
- Remove `onLongPress` from the renderer's `build(...)` call entirely.
- Add `sketchActive: bool` and `onSketchTap(lat, lng)` params to `MapRenderer.build(...)`. When `sketchActive`, the existing onTap listeners (point click handler, road click handler, polygon click handler) early-return; only `onSketchTap` fires.
- The existing reshape overlay renders vertex/midpoint handles from `workingRings`. One-line change: render even when `originalFeature == null`, gated on `isActive` instead.
- Replace the blue "long-press the map" hint banner with `GeometryEditorBanner` (renamed) when sketch is active. The banner labels its primary button **Finish** in sketch mode and **Save** in reshape mode.

## Analytics

Add events mirroring the existing `map.reshape.*` shape:

- `map.sketch.entered` — `feature_type`
- `map.sketch.completed` — `feature_type`, `vertex_count`, `ops_made`
- `map.sketch.cancelled` — `feature_type`, `vertex_count`, `ops_made`
- `map.sketch.validation_failed` — `feature_type`, `rule`

## Testing

### Unit — `GeometryEditorController` sketch ops
New `test/features/map/geometry_editor/geometry_editor_controller_sketch_test.dart`:

- `enterSketch('building')` → empty closed ring, `isSketchMode == true`, `pendingFeatureType == 'building'`
- `appendVertex` × 3 → 3 vertices, 3 `Add` ops on stack
- `undo` after 3 appends → 2 vertices, 2 ops on stack
- `removeVertex(0)` → top of stack is `Remove`
- `appendVertex` for `point` after 1 already exists → vertex 0 replaced (treated as `Move`); ring length stays 1
- `cancelSketch` → state reset, `isActive == false`
- `finishSketch` happy path × 3 (building/road/point) → repo called with correct GeoJSON shape, returns inserted Feature, state cleared
- `finishSketch` validation failures → no DB write, vertices preserved, specific error returned

### Unit — existing reshape behavior
All current `reshape_*_test.dart` files must pass after rename. Spot-fix imports only.

### Unit — validators
- `validatePolyline` — passes for ≥2 distinct vertices, fails on coincident-adjacent and on length<2
- `validateBuildingPolygon` is reused unchanged — no new test

### Widget — sketch flow
New `test/features/map/sketch_flow_test.dart`:

- Tap `+` pill → type picker appears
- Pick Building → banner appears `0 vertices • building`, Finish disabled
- Tap map 3 times → banner shows `3 vertices`, Finish enabled, polygon preview rendered
- Tap a vertex handle → vertex removed, `2 vertices`, Finish disabled
- Drag a vertex handle → `Move` op recorded, undo enabled
- Hit Finish → repo called with closed-ring Polygon GeoJSON, navigation to `/feature/{id}`
- Repeat for Road (2 taps min) and Point (1 tap min)
- Cancel with 0 vertices → banner gone, no dialog
- Cancel with ≥1 vertex → confirm dialog; "Discard" exits, "Keep editing" stays

### Widget — validation failures
- Building with 3 vertices, one outside boundary → snackbar names the vertex, state preserved
- Building with 4 vertices producing self-intersection → self-intersection snackbar, state preserved
- Road with 2 coincident vertices → zero-length-edge snackbar, state preserved

### Widget — gesture suppression in sketch mode
- With sketch active, tap on existing rendered feature → no navigation, no form
- With sketch active, long-press anywhere → no-op
- Without sketch, tap + long-press behave per today

### Integration
The skipped integration test from commit `3febd33` (set-up-complete-feature flow) is unskipped and updated to drive the new sketch flow end-to-end: home → Get Maps → download → Open Map → tap `+` → pick Building → tap 4 times → Finish → fill form → Done → new feature visible on map.

## Out of scope / deferred

- Pre-existing test failures noted in observation 2889 — not on the sketch path.
- Submission detail screen still uses `context.go('/map')` at `submission_detail_screen.dart:337` — separate fix, tracked elsewhere.
- Live validation while sketching — explicitly rejected during brainstorming.
- Holes / multi-part geometry — Drift schema and validators are single-ring today.

## Files touched (preview, not exhaustive)

**Renamed:**
- `lib/features/map/reshape/**` → `lib/features/map/geometry_editor/**` (folder + class names)

**Modified:**
- `lib/features/map/presentation/map_screen.dart` — drop `_addModeActive`, drop `_handleLongPress`, add `_onPlusPressed`; bind banner to `editorState.isActive`
- `lib/features/map/presentation/map_renderer.dart` — add `sketchActive` + `onSketchTap`; remove `onLongPress` plumbing
- `lib/features/new_feature/data/new_feature_repository.dart` — add `createFeature(...)`; delete `createNewFeature(lat, lng)`
- `lib/features/map/geometry_editor/presentation/geometry_editor_overlay.dart` — render when `isActive`, not `originalFeature != null`
- `lib/features/map/geometry_editor/presentation/geometry_editor_banner.dart` — Finish/Save label switches on `isSketchMode`

**Added:**
- `lib/core/geo/polyline_validator.dart` (small)
- `test/features/map/geometry_editor/geometry_editor_controller_sketch_test.dart`
- `test/features/map/sketch_flow_test.dart`
- L10n strings: `sketchBannerTitle`, `sketchFinishLabel`, `sketchCancelLabel`, `sketchDiscardConfirmTitle`, `sketchDiscardConfirmBody`, `sketchMinVerticesError` (per type)

**Deleted:**
- `_handleLongPress` and the `onLongPress` plumbing through the renderer
- `NewFeatureRepository.createNewFeature(lat, lng)`
