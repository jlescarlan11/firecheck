# Road Feature Rendering Design

## Goal

Render road features (LineString geometry) as coloured polyline overlays on the map, make them tappable to open the road survey form, and fix the `markFeatureStatus` bug so road status updates propagate to line colour without a full map reload.

## Background

`MapboxMapRenderer._renderFeatures()` runs every non-new feature through `_decodePolygon()` and silently skips any feature that returns `null`. Roads have LineString geometry — `_decodePolygon()` cannot parse them, so they are invisible and untappable. The renderer also has no `PolylineAnnotationManager`, so even if decoding succeeded there is no surface to draw lines on.

A secondary bug in `FeatureRepository.markFeatureStatus` always joins `buildingAttributes` regardless of feature type, so road survey saves never advance the feature status to `'complete'`, breaking the live colour-update requirement.

The road survey form (`lib/features/survey/road_form/`) is fully implemented. `MapScreen._handleFeatureTap()` and `SubmissionDetailScreen` are already road-aware. The only missing pieces are rendering and the status bug.

## Architecture

Changes are confined to three files plus new tests.

| File | Change |
|------|--------|
| `lib/features/map/presentation/map_renderer.dart` | Add `_roadManager`, `_decodeLineString()`, dispatch in render loop, polyline tap listener, symmetric dispose |
| `lib/core/db/feature_repository.dart` | Fix `markFeatureStatus` — branch on `featureType` before attribute join |
| `test/features/map/map_renderer_test.dart` | Add unit tests for LineString decoding, status-colour mapping, malformed geometry |
| `test/features/map/map_screen_road_test.dart` | New widget tests: road renders, road tap, colour update after save |
| `test/core/db/feature_repository_test.dart` | Add: road feature status advances to `'complete'` after save |

`lib/features/map/presentation/map_screen.dart` requires no changes.

## Renderer Changes

### `_decodeLineString()`

Mirrors `_decodePolygon()`. Parse `geometryGeojson` as JSON, verify `type == 'LineString'`, extract `coordinates` as `List<List<double>>`, check `coordinates.length >= 2`, return `List<Position>` or `null` on any failure. Called only for `featureType == 'road'`.

### `_roadManager` (`PolylineAnnotationManager`)

- Created in `_onMapCreated` immediately after `_featureManager`.
- Cleared via `.deleteAll()` at the top of `_renderFeatures()` alongside existing clear calls.
- Disposed in `dispose()` symmetrically.
- Registered after `_featureManager` so road polylines draw above building fills but below `_pointManager` (new-feature dots).

### Render Loop Dispatch

```
for each non-new feature:
  if featureType == 'road':
    coords = _decodeLineString(feature.geometryGeojson)
    if coords == null: log warning, continue
    _roadManager.create(PolylineAnnotationOptions(
      geometry: LineString(coordinates: coords),
      lineColor: _colorForStatus(feature.status),
      lineWidth: 8.0,
      data: feature.id,   // for tap resolution
    ))
  else:
    polygon = _decodePolygon(...)   // existing path unchanged
```

Line width is **8 px solid**, visually distinct from the basemap road layer.

### Tap Listener

Registered on `_roadManager` in `_onMapCreated`. Resolves the tapped annotation's `data` field to a feature ID and calls the same `onFeatureTap` callback used by building polygons. `MapScreen._handleFeatureTap()` already dispatches on `featureType == 'road'` to compute a polyline midpoint and navigate to the road survey form.

### Colour

`_colorForStatus()` is unchanged — road polylines pass `feature.status` into the same function buildings use:

| Status | Colour |
|--------|--------|
| `'complete'` | Green `0xFF276749` |
| `'in_progress'` | Orange `0xFFB7791F` |
| anything else | Red `0xFFC53030` |

## `markFeatureStatus` Bug Fix

Current code always joins `buildingAttributes`, so road surveys never advance to `'complete'`. Fix: branch on `featureType` before the join.

```
if featureType == 'building':
    join buildingAttributes
else if featureType == 'road':
    join roadAttributes
```

After a road form save the repository correctly writes `status = 'complete'`, the renderer's stream re-emits the feature, and `_renderFeatures()` redraws the polyline in green without a full map reload.

## Error Handling & Logging

- `_decodeLineString()` returns `null` for: non-LineString type, malformed JSON, fewer than 2 coordinates.
- On `null`, the render loop logs: `[MapRenderer] skipped road feature {id}: invalid LineString geometry` and continues — no crash.
- Tap with unresolvable feature ID: logs a warning and does nothing (same pattern as building tap handler).

## Testing

### Renderer Unit Tests (`test/features/map/map_renderer_test.dart`)

1. `_decodeLineString` returns valid `List<Position>` for well-formed LineString GeoJSON.
2. `_decodeLineString` returns `null` for Polygon GeoJSON (wrong type).
3. `_decodeLineString` returns `null` for malformed JSON.
4. `_decodeLineString` returns `null` for LineString with fewer than 2 coordinates.
5. Status-to-colour: `'complete'` → `0xFF276749`, `'in_progress'` → `0xFFB7791F`, `'not_started'` → `0xFFC53030`.

### Widget Tests (`test/features/map/map_screen_road_test.dart`)

1. Road line renders — seed road feature, pump map widget, assert `PolylineAnnotation` exists with correct colour.
2. Road line tap opens survey form — tap annotation, assert `SubmissionDetailScreen` (road path) is pushed.
3. Colour updates after status change — seed road as `'not_started'` (red), save road form, assert polyline colour updates to green without full map reload.

### Repository Test (`test/core/db/feature_repository_test.dart`)

1. After inserting road feature + road attributes + calling `markFeatureStatus`, status becomes `'complete'`.

## Out of Scope

- Reshape or vertex editing of road geometry.
- Creating new road features from the map.
- Changes to `MapScreen._handleFeatureTap()` or `SubmissionDetailScreen`.
