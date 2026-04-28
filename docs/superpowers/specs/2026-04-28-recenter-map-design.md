# FireCheck Mobile — Recenter Map Design Spec

**Date:** 2026-04-28
**Status:** Draft v1 (brainstorming output)
**Story:** US-12 — As an enumerator, I want a button to recenter the map on my current GPS location
**Parent spec:** `docs/superpowers/specs/2026-04-24-firecheck-mobile-design.md`
**Related:** `docs/superpowers/specs/2026-04-24-firecheck-phase-1-design.md` (map screen architecture)

## 1. Summary

Add a one-tap **recenter** button to the map screen that flies the camera to the enumerator's current GPS position. Replaces the dead "Follow me" pill that exists in `map_screen.dart` today. Continuous follow mode and compass-based rotation are explicit non-goals (separate stories).

After this ships:

1. The map screen opens framed on the assignment boundary (no more hard-coded Cebu fallback coordinate).
2. A circular `Icons.my_location` button sits at the bottom-right of the map.
3. On tap with permission already granted, it flies to the most recent GPS fix if accurate (≤100 m), or shows a brief "Locating you…" loading state while waiting up to 8 s for an accurate fix.
4. On tap with permission not yet asked, a rationale dialog appears before the OS prompt.
5. On tap with permission permanently denied, a non-blocking snackbar offers a shortcut to device settings.
6. On 8 s timeout, the camera best-effort recenters to the latest available position with a low-accuracy warning snackbar.
7. Each tap fires an analytics event through a new `AnalyticsService` interface (no-op default, console logging in debug builds).

## 2. Scope

### In scope

- **`RecenterButton` widget** — pure-UI `StatelessWidget` keyed off a `RecenterButtonState` enum (`idle | loading | disabled`). Lives at `lib/features/map/presentation/recenter_button.dart`.
- **`CameraTarget` value type** — immutable record `(lat, lng, zoom, requestId)` passed into the renderer to drive camera changes. Equality is by `requestId` so identical-coordinate re-taps still trigger a fly. Lives at `lib/features/map/presentation/camera_target.dart`.
- **`MapRenderer.build()` signature change** — gains `CameraTarget? cameraTarget` and `CameraTarget? initialCameraTarget` parameters. Real renderer reacts to changes in `didUpdateWidget` via `MapboxMap.flyTo`. Fake renderer records targets received for test assertions.
- **Initial camera framing from assignment boundary** — new pure-Dart helper `lib/core/geo/polygon_bounds.dart` computes a bounding-box centroid and zoom-to-fit from the assignment boundary GeoJSON. Replaces the hard-coded `(123.88270, 10.31810)` zoom-15 fallback in `map_renderer.dart:147-149`.
- **`_onRecenterTap()` orchestration** — added to `_MapScreenState`. Permission check → cached-if-accurate → slow-path with timeout → analytics → snackbars. Sequence-numbered to prevent stale completions.
- **`LocationService` interface changes** — adds `checkPermission()` (pure check, no prompt, separate from existing `requestPermission()`) and `openAppSettings()`. `GeolocatorLocationService` and `FakeLocationService` updated.
- **Permission UX**:
  - Rationale dialog before the first OS prompt (AC4)
  - Non-blocking snackbar with "Open settings" action when `deniedForever` (AC5)
  - Removes the `Future.microtask(requestPermission)` on-mount kick at `map_screen.dart:39-41` — permission is now asked on first recenter tap, gated by the rationale.
- **`AnalyticsService` stub** — new `lib/core/analytics/` directory:
  - `analytics_service.dart` — interface + `NoopAnalyticsService` + `ConsoleAnalyticsService` (debugPrint-backed) + `RecordingAnalyticsService` (test double)
  - `analytics_providers.dart` — Riverpod provider; `ConsoleAnalyticsService` in `kDebugMode`, `NoopAnalyticsService` otherwise.
- **Delete dead "Follow me" pill** — remove `_followMe` state field and its pill from `map_screen.dart:30, 104-108`.
- **i18n** — new ARB keys for the rationale dialog, three snackbars, and the button's semantic label.

### Out of scope

- Continuous follow mode (locks camera to user movement) — separate story.
- Compass / heading-based map rotation — separate story.
- Replacing the in-screen `_resolvePosition()` flow used by feature taps — out of scope; this story only adds a new recenter affordance, not refactoring existing GPS use sites.
- Real analytics backend — `NoopAnalyticsService` is the production default; future story swaps in PostHog/Supabase/Firebase.
- Auto-recovery after the user returns from device settings — user re-taps recenter manually.
- Persistent / inline GPS-quality indicator on the button itself — the snackbar is the only quality surface.

## 3. Architecture

### Files added

```
lib/core/analytics/
  analytics_service.dart         # interface + Noop + Console + Recording impls
  analytics_providers.dart       # Riverpod analyticsServiceProvider
lib/core/geo/
  polygon_bounds.dart            # centroid + zoom-to-fit for boundary GeoJSON
lib/features/map/presentation/
  camera_target.dart             # CameraTarget value type
  recenter_button.dart           # pure UI widget
  recenter_button_state.dart     # enum: idle | loading | disabled
```

### Files changed

```
lib/core/location/
  location_service.dart          # adds checkPermission(), openAppSettings();
                                 # FakeLocationService gains test recorders
lib/features/map/presentation/
  map_screen.dart                # delete _followMe + pill; add _onRecenterTap;
                                 # mount RecenterButton; pass cameraTarget +
                                 # initialCameraTarget to renderer
  map_renderer.dart              # build() takes cameraTarget + initialCameraTarget;
                                 # _MapboxMapView stores MapboxMap?, flies on
                                 # didUpdateWidget; FakeMapRenderer records targets
lib/l10n/
  app_en.arb (and other locales) # new keys (see §8)
```

### Information flow on tap

```
User tap RecenterButton
      ↓
_MapScreenState._onRecenterTap()
      ↓
  permission check
   ├── denied        → rationale dialog → OS prompt
   ├── deniedForever → snackbar with Open Settings action (AC5)
   └── granted       ↓
  cached fix?
   ├── present + ≤100m  → setState cameraTarget → renderer flies → analytics.track
   └── stale or missing ↓
  setState _recenterState = loading (button shows spinner)
      ↓
  await positionStream().firstWhere(accuracy ≤ 100m).timeout(8s)
   ├── accurate  → setState cameraTarget → idle → analytics.track
   └── timeout   → cameraTarget = best-effort latest;
                   low-accuracy snackbar; idle → analytics.track
```

## 4. Components

### 4.1 `RecenterButton` (pure UI)

```dart
class RecenterButton extends StatelessWidget {
  const RecenterButton({super.key, required this.state, required this.onTap});

  final RecenterButtonState state;   // idle | loading | disabled
  final VoidCallback onTap;
}
```

**Visuals:**

| State | Icon | Tap | Other |
|---|---|---|---|
| `idle` | `Icons.my_location` | invokes `onTap` | filled circle, accent color |
| `loading` | `CircularProgressIndicator(strokeWidth: 2)`, 20 dp | no-op | filled circle, accent color |
| `disabled` | `Icons.my_location` | no-op | 50% opacity, no ripple |

**Sizing:** circular 48 dp tap target (Material guideline minimum). Semantic label `recenterButtonSemanticLabel`.

**Placement on the screen:** `Positioned(right: 16, bottom: 84)` in the existing `Stack` in `map_screen.dart`. The 84 dp bottom offset clears the existing add-feature pill row at `bottom: 18` and the read-only banner.

**Why no permission-denied visual state on the button:** the rationale dialog and the deniedForever snackbar are transient. Encoding permission state in the button visual would require a continuous permission-stream subscription that complicates the widget for marginal value.

**Why no live GPS-quality badge:** AC6 surfaces accuracy via a snackbar, not a button state. A live indicator would require continuous accuracy subscription and double up the messaging.

### 4.2 `CameraTarget`

```dart
@immutable
class CameraTarget {
  const CameraTarget({
    required this.lat,
    required this.lng,
    required this.zoom,
    required this.requestId,
  });

  final double lat;
  final double lng;
  final double zoom;
  final int requestId;

  @override
  bool operator ==(Object other) =>
      other is CameraTarget && other.requestId == requestId;
  @override
  int get hashCode => requestId.hashCode;
}
```

Equality on `requestId` only, so the renderer's `oldWidget.cameraTarget != widget.cameraTarget` check fires whenever a new tap occurs — even if the user taps recenter twice at the same physical location.

### 4.3 `MapRenderer` interface change

```dart
abstract class MapRenderer {
  Widget build(
    BuildContext context, {
    required List<Feature> features,
    required String boundaryGeojson,
    required void Function(Feature) onFeatureTap,
    void Function(double lat, double lng)? onLongPress,
    bool addModeActive,
    CameraTarget? cameraTarget,           // NEW
    CameraTarget? initialCameraTarget,    // NEW
  });
}
```

Two camera props because they have different lifecycles:

- **`initialCameraTarget`** — set once when the screen first builds (computed from the assignment boundary). Drives the renderer's initial `cameraOptions`.
- **`cameraTarget`** — changes over time as the user taps recenter. The renderer reacts in `didUpdateWidget`.

**`_MapboxMapView`** stores its `MapboxMap?` reference in a private field set during `_onMapCreated`. Adds:

```dart
@override
void didUpdateWidget(covariant _MapboxMapView oldWidget) {
  super.didUpdateWidget(oldWidget);
  // ... existing feature/boundary re-render ...
  if (widget.cameraTarget != null &&
      widget.cameraTarget != oldWidget.cameraTarget) {
    unawaited(_flyToCameraTarget(widget.cameraTarget!));
  }
}

Future<void> _flyToCameraTarget(CameraTarget t) async {
  final map = _mapboxMap;
  if (map == null) return;  // _onMapCreated hasn't run yet
  await map.flyTo(
    CameraOptions(
      center: Point(coordinates: Position(t.lng, t.lat)),
      zoom: t.zoom,
    ),
    MapAnimationOptions(duration: 750),  // smooth animation, AC2
  );
}
```

**`FakeMapRenderer`** gains:

```dart
CameraTarget? lastCameraTarget;
CameraTarget? lastInitialCameraTarget;
final List<CameraTarget> cameraTargetHistory = [];
```

These get populated in `build`, becoming the assertion seams for widget tests.

**Mapbox location component** at `map_renderer.dart:166-172` is unchanged (`LocationComponentSettings(enabled: true, pulsingEnabled: true)`). It already covers AC3 (location indicator / puck).

### 4.4 `_onRecenterTap()` orchestration

New state on `_MapScreenState`:

```dart
RecenterButtonState _recenterState = RecenterButtonState.idle;
CameraTarget? _cameraTarget;          // passed into MapRenderer.build()
int _recenterRequestSeq = 0;          // monotonic
bool _rationaleVisible = false;       // guards re-entry while dialog is open
```

```dart
Future<void> _onRecenterTap() async {
  if (_recenterState != RecenterButtonState.idle) return;
  if (_rationaleVisible) return;

  // Single increment per tap — used both for slow-path supersedence
  // detection AND as the CameraTarget.requestId for renderer dedup.
  final seq = ++_recenterRequestSeq;

  final analytics = ref.read(analyticsServiceProvider);
  final locationService = ref.read(locationServiceProvider);

  // ── Permission gate (AC4 / AC5) ─────────────────────────────────────
  var perm = await locationService.checkPermission();
  if (perm == LocationPermission.denied) {
    final allow = await _showLocationRationale();
    if (allow != true) {
      analytics.track('map.recenter.tapped',
        properties: {'outcome': 'permission_rationale_dismissed'});
      return;
    }
    perm = await locationService.requestPermission();
  }

  if (perm == LocationPermission.deniedForever ||
      perm == LocationPermission.unableToDetermine) {
    _showSettingsShortcutSnackbar();
    analytics.track('map.recenter.tapped',
      properties: {'outcome': 'permission_denied_forever'});
    return;
  }
  if (perm == LocationPermission.denied) {
    analytics.track('map.recenter.tapped',
      properties: {'outcome': 'permission_denied'});
    return;
  }

  // Permission dialogs are async; bail if a newer tap superseded us.
  if (seq != _recenterRequestSeq) return;

  // ── Cached-if-accurate fast path ────────────────────────────────────
  final cached = ref.read(currentPositionProvider).valueOrNull;
  if (cached != null && cached.accuracy <= 100.0) {
    _flyTo(cached, seq: seq);
    analytics.track('map.recenter.tapped',
      properties: {'outcome': 'recentered_from_cache',
                   'accuracy_m': cached.accuracy.round()});
    return;
  }

  // ── Slow path: wait for accurate fix, up to 8s (AC6 / AC7) ──────────
  setState(() => _recenterState = RecenterButtonState.loading);

  try {
    final accurate = await locationService
        .positionStream()
        .firstWhere((p) => p.accuracy <= 100.0)
        .timeout(const Duration(seconds: 8));

    if (!mounted || seq != _recenterRequestSeq) return;
    _flyTo(accurate, seq: seq);
    analytics.track('map.recenter.tapped',
      properties: {'outcome': 'recentered_after_wait',
                   'accuracy_m': accurate.accuracy.round()});
  } on TimeoutException {
    if (!mounted || seq != _recenterRequestSeq) return;
    final best = ref.read(currentPositionProvider).valueOrNull;
    if (best != null) _flyTo(best, seq: seq);
    _showLowAccuracySnackbar();
    analytics.track('map.recenter.tapped',
      properties: {'outcome': 'low_accuracy_timeout',
                   'accuracy_m': best?.accuracy.round()});
  } finally {
    if (mounted && seq == _recenterRequestSeq) {
      setState(() => _recenterState = RecenterButtonState.idle);
    }
  }
}

void _flyTo(Position p, {required int seq}) {
  setState(() {
    _cameraTarget = CameraTarget(
      lat: p.latitude,
      lng: p.longitude,
      zoom: 17,           // midpoint of AC2's 16–18 range
      requestId: seq,
    );
  });
}
```

**Notes on subtle bits:**

1. **`_recenterRequestSeq` is incremented exactly once per tap**, at the very top of `_onRecenterTap`. The same `seq` value is used both to detect supersedence (a later tap bumped the counter, so this completion is stale) and as the `CameraTarget.requestId` (so the renderer's `didUpdateWidget` flies once per tap, even if two taps fly to identical coordinates). Crucially, `_flyTo` does *not* re-increment, so the `finally` block's `seq == _recenterRequestSeq` check stays valid after a successful fly.
2. **Slow path subscribes to `positionStream()` directly** rather than re-using `currentPositionProvider`. Using `firstWhere` on the provider's shared stream would consume the matching emission for everyone else.
3. **`Geolocator.openAppSettings()`** is called from the snackbar's `SnackBarAction` for AC5. Wrapped in `LocationService.openAppSettings()` for the test seam.
4. **AC8 (offline behavior)** is satisfied implicitly. Geolocator is independent of network; existing tile cache from Phase 1 handles map tiles. No new code, only verified by manual QA.
5. **AC9 (battery)** is satisfied without new code. `currentPositionProvider` is auto-disposed on screen unmount; the `whileInUse` permission means iOS/Android pause GPS when backgrounded; the slow-path subscription is per-tap.

### 4.5 Permission flow detail

`Geolocator.checkPermission()` returns five values; this feature collapses them into three branches:

| Geolocator value | Branch | UX |
|---|---|---|
| `whileInUse` / `always` | granted | proceed to recenter |
| `denied` | askable | rationale dialog → OS prompt |
| `deniedForever` / `unableToDetermine` | dead-end | snackbar with settings shortcut |

**Rationale dialog (AC4)**:
- Title: `locationRationaleTitle` — "Use your location"
- Body: `locationRationaleBody` — "FireCheck uses your GPS to center the map on you so you can quickly orient yourself in the field. We only access location while you have the app open."
- Actions: `locationRationaleNotNow` ("Not now", returns false) | `locationRationaleAllow` ("Allow", returns true)
- `_rationaleVisible` is set to true while the dialog is on-screen so a stray second tap on the recenter button doesn't double-stack dialogs.

**`deniedForever` snackbar (AC5)**:
- Content: `locationSnackbarPermanentlyDenied` — "Location permission denied. Open settings to enable it."
- Action: `SnackBarAction(label: locationSnackbarOpenSettings, onPressed: locationService.openAppSettings)`
- Duration: 6 seconds (longer than default 4 s for read time).

**Settings round-trip:** when the user returns from settings, they re-tap recenter manually. We do not auto-recover via lifecycle resume — adds complexity and feels presumptuous.

**Removed code:** the on-mount `Future.microtask(requestPermission)` at `map_screen.dart:39-41` is deleted. The first permission ask now happens on the first recenter tap, gated by the rationale.

### 4.6 Initial camera framing

`lib/core/geo/polygon_bounds.dart`:

```dart
class PolygonBounds {
  PolygonBounds({required this.center, required this.zoom});
  final LatLng center;
  final double zoom;
}

PolygonBounds? polygonBoundsFromGeojson(String geojson, {Size viewport});
```

Algorithm:
1. Decode GeoJSON polygon, walk all coordinates, compute min/max lat and lng.
2. Centroid = `((minLat+maxLat)/2, (minLng+maxLng)/2)`.
3. Zoom-to-fit: derive zoom from the bounding-box diagonal in meters using the standard `156543.03 * cos(lat) / 2^zoom` ground-resolution formula, capped at 18 (avoid over-zoom on tiny boundaries) and floored at 12.
4. Returns null if GeoJSON is empty or malformed.

In `_MapScreenState.build()`:

```dart
final bounds = polygonBoundsFromGeojson(assignment.boundaryPolygonGeojson);
final initialTarget = bounds != null
    ? CameraTarget(
        lat: bounds.center.lat,
        lng: bounds.center.lng,
        zoom: bounds.zoom,
        requestId: 0,    // initial frame is always seq 0
      )
    : null;
```

The renderer falls back to a sensible default (Mapbox default world view, or a hard-coded local default) only if `initialCameraTarget` is null. Replaces the current hard-coded `(123.88270, 10.31810)` zoom 15 in `map_renderer.dart:147-149`.

### 4.7 `AnalyticsService` stub

```dart
abstract class AnalyticsService {
  void track(String event, {Map<String, Object?>? properties});
}

class NoopAnalyticsService implements AnalyticsService { ... }
class ConsoleAnalyticsService implements AnalyticsService { ... }  // debugPrint-backed
class RecordingAnalyticsService implements AnalyticsService { ... }  // test double
```

Provider:

```dart
final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return kDebugMode
      ? const ConsoleAnalyticsService()
      : const NoopAnalyticsService();
});
```

**Events fired by this story** — single event name `map.recenter.tapped`, varied by `outcome`:

| Outcome | Fires when |
|---|---|
| `recentered_from_cache` | Cached fix was ≤ 100 m, used immediately |
| `recentered_after_wait` | Slow path got an accurate fix within 8 s |
| `low_accuracy_timeout` | 8 s timed out; best-effort recenter + warning |
| `permission_rationale_dismissed` | User tapped "Not now" on rationale dialog |
| `permission_denied` | OS prompt was declined this time |
| `permission_denied_forever` | Permission permanently blocked, snackbar shown |

Properties always include `accuracy_m` (rounded int) when a `Position` was involved.

## 5. Acceptance criteria mapping

| AC | Mechanism |
|---|---|
| **AC1** Button visibility / placement | `RecenterButton` in `Positioned(right: 16, bottom: 84)`; doesn't overlap add-feature pill row at `bottom: 18`. |
| **AC2** Recenter on tap | `_onRecenterTap` → `_flyTo` → `CameraTarget(zoom: 17)` → renderer's `flyTo` with `MapAnimationOptions(duration: 750)`. |
| **AC3** Location indicator | Mapbox `LocationComponentSettings(enabled: true, pulsingEnabled: true)` already enabled at `map_renderer.dart:166-172`. |
| **AC4** Permission not granted | Rationale dialog → OS prompt; outcome events `permission_rationale_dismissed` or `permission_denied`. |
| **AC5** Permission denied permanently | Non-blocking snackbar with "Open settings" `SnackBarAction` calling `locationService.openAppSettings()`. |
| **AC6** GPS unavailable / weak signal | Slow path waits for `accuracy ≤ 100 m`; on 8 s timeout, best-effort recenter + low-accuracy snackbar. |
| **AC7** Loading state | Button transitions to `RecenterButtonState.loading` on slow path; renders spinner. |
| **AC8** Offline behavior | GPS independent of network (Geolocator); existing tile cache from Phase 1 unchanged. Verified by manual QA. |
| **AC9** Battery efficiency | `currentPositionProvider` auto-disposes on screen unmount; `whileInUse` permission means OS pauses GPS when backgrounded; slow-path subscription is per-tap. No long-lived high-accuracy tracking added. |

## 6. Testing strategy

### 6.1 Unit tests (no widgets)

- **`test/core/analytics/analytics_service_test.dart`**:
  - `ConsoleAnalyticsService` formats events to `debugPrint` (override `debugPrint` to a buffer; verify output)
  - `NoopAnalyticsService.track` is a no-op
  - `RecordingAnalyticsService` records event + properties in order
- **`test/core/geo/polygon_bounds_test.dart`**:
  - Centroid of a known polygon returns expected lat/lng within 1e-6
  - Zoom-to-fit picks 18 for tiny polygons, 12 for huge polygons, monotonic between
  - Empty / malformed GeoJSON returns null

### 6.2 Widget tests (no Mapbox plugin)

- **`test/features/map/recenter_button_test.dart`** (pure widget, no providers):
  - `idle` renders `Icons.my_location`, taps invoke `onTap`
  - `loading` renders `CircularProgressIndicator`, taps do not invoke `onTap`
  - `disabled` renders at 50% opacity, taps do not invoke `onTap`
  - Has the `recenterButtonSemanticLabel` semantic label
- **`test/features/map/map_screen_recenter_test.dart`** (full screen with `FakeMapRenderer` + `FakeLocationService` + `RecordingAnalyticsService`):

| AC | Test |
|---|---|
| AC1 | Button rendered at bottom-right; doesn't overlap add-feature pill |
| AC2 (cache hit) | Cached fix accuracy=20 m → tap → `fakeRenderer.cameraTargetHistory.last.zoom == 17` and lat/lng match cached; analytics outcome `recentered_from_cache` |
| AC2 (slow path) | No cached fix; stream emits 200 m then 50 m within 1 s → camera target eventually set; outcome `recentered_after_wait` |
| AC4 (rationale → allow) | `denied` then `whileInUse` → tap → rationale dialog → "Allow" → permission requested → outcome `recentered_from_cache` |
| AC4 (rationale → not now) | Same but tap "Not now" → no permission requested → outcome `permission_rationale_dismissed`; no camera target change |
| AC5 | `deniedForever` → tap → snackbar with "Open settings" action → tap action → `fakeLocationService.openAppSettingsCalled == true`; outcome `permission_denied_forever` |
| AC6 / AC7 | Stream emits only 250 m fixes for 8 s → button transitions `idle → loading → idle`, low-accuracy snackbar shown, camera best-effort recentered, outcome `low_accuracy_timeout` |
| AC9 (smoke) | Code-comment assertion: `currentPositionProvider` has no `keepAlive`; slow-path subscription is local to the tap handler. |

### 6.3 Manual / device QA — Definition of Done

- [ ] iOS — first install, tap recenter → rationale → OS prompt → puck appears, map flies in
- [ ] iOS — denied at OS prompt, tap again → "Not now" path, then re-tap and grant
- [ ] iOS — settings → toggle off "While using the app", return → tap recenter → AC5 snackbar
- [ ] Android — same three paths
- [ ] Indoor (bad GPS) — tap recenter → "Locating you…" spinner → after 8 s, low-accuracy snackbar + best-effort recenter
- [ ] Dense urban / rural — verify accuracy threshold of 100 m is realistic; flag in PR if it should be tuned
- [ ] Battery: leave app foregrounded for 5 min after a recenter → confirm CPU profiler shows GPS quiescent (or only the 3 m-distance-filtered baseline ticks)
- [ ] Min supported OS — Android API 24, iOS 14 (per existing project baseline)

### 6.4 Integration test — out of scope

Existing skipped Flow F skeleton (commit `3287943`) is not extended in this story.

## 7. Open questions

None — all brainstorming questions resolved (see §9 history).

## 8. i18n keys (final list)

| Key | English |
|---|---|
| `recenterButtonSemanticLabel` | Recenter map on my location |
| `locationRationaleTitle` | Use your location |
| `locationRationaleBody` | FireCheck uses your GPS to center the map on you so you can quickly orient yourself in the field. We only access location while you have the app open. |
| `locationRationaleAllow` | Allow |
| `locationRationaleNotNow` | Not now |
| `locationSnackbarPermanentlyDenied` | Location permission denied. Open settings to enable it. |
| `locationSnackbarOpenSettings` | Open settings |
| `locationSnackbarLowAccuracy` | Location accuracy is low. Showing your approximate position. |

## 9. Brainstorming history

Decisions resolved during the 2026-04-28 brainstorm session:

1. **Existing dead "Follow me" pill:** delete entirely, replace with circular recenter button bottom-right.
2. **Tap freshness/quality strategy:** cached-if-accurate (≤ 100 m), else wait up to 8 s for an accurate fix.
3. **8 s timeout fallback:** best-effort recenter to the latest available position + low-accuracy warning snackbar.
4. **Analytics:** add minimal `AnalyticsService` stub now (no-op default, console-logger in debug); don't defer.
5. **Initial camera framing:** auto-frame to the assignment boundary on first map open; permission ask deferred to first recenter tap (no on-mount kick).
6. **Implementation approach:** extract `RecenterButton` as a pure widget; keep orchestration in `_MapScreenState`. (Approach 1 of 3.)
7. **Settings round-trip recovery:** user re-taps recenter manually after returning from device settings; no lifecycle-based auto-recovery.
