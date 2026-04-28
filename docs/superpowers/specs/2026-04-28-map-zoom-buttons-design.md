# FireCheck Mobile — Map Zoom Buttons Design Spec

**Date:** 2026-04-28
**Status:** Draft v1 (brainstorming output)
**Story:** US-13 — As an enumerator, I want explicit zoom-in and zoom-out buttons in addition to pinch gestures, so that I can adjust the map one-handed or with gloves on.
**Parent spec:** `docs/superpowers/specs/2026-04-24-firecheck-mobile-design.md`
**Related:**
- `docs/superpowers/specs/2026-04-24-firecheck-phase-1-design.md` (map screen architecture)
- `docs/superpowers/specs/2026-04-28-recenter-map-design.md` (sibling story; established `CameraTarget`, `MapRenderer` interface, `RecenterButton` styling, analytics plumbing)

## 1. Summary

Add two circular zoom buttons (`+` and `−`) stacked above the existing `RecenterButton` on the right edge of the map screen. Each tap eases the camera ±1 zoom level over ~250 ms, anchored on the current map center. Buttons disable at the Mapbox style's absolute bounds (zoom 0 / 22). Pinch-to-zoom continues to work unchanged and feeds the same disabled-state logic via a new camera-change subscription on the renderer.

After this ships:

1. The map screen shows three stacked circular controls on its right edge: zoom-in (+), zoom-out (−), recenter — top to bottom.
2. Tapping zoom-in/out animates the camera by exactly one zoom level over ~250 ms, centered on the current map center.
3. The zoom-in button visually disables at zoom 22; the zoom-out button at zoom 0.
4. Pinching to zoom updates the disabled state in real time (e.g., pinch out to 22 → zoom-in button becomes disabled within one frame of the rounded zoom changing).
5. Each tap fires a `map.zoom.tapped` analytics event with `direction` and `from_zoom` properties.
6. The existing recenter button continues to work exactly as it does today (its 750 ms `flyTo` animation is preserved via a new `CameraAnimation.fly` default).

## 2. Scope

### In scope

- **`ZoomButton` widget** — pure-UI `StatelessWidget`, 48×48 circular, primary fill, mirroring `RecenterButton`'s style. Lives at `lib/features/map/presentation/zoom_button.dart`.
- **`ZoomButtonState` enum** — `idle | disabled` (no `loading` — zoom is not async). Lives at `lib/features/map/presentation/zoom_button_state.dart`.
- **`ZoomDirection` enum** — `zoomIn | zoomOut` (button param). Lives at `lib/features/map/presentation/zoom_direction.dart`.
- **`CameraAnimation` enum** — `fly | ease`. Added to `lib/features/map/presentation/camera_target.dart`.
- **`CameraTarget` extension** — gains `CameraAnimation animation` field, default `fly`. Equality remains `requestId`-only.
- **`MapRenderer.build()` signature change** — gains optional `void Function(double zoom, double lat, double lng)? onCameraChanged`. Real renderer subscribes to the native camera-change listener; fake exposes a `simulateCameraChanged` test seam. Real renderer also picks `easeTo`/`flyTo` based on `cameraTarget.animation`.
- **`_MapScreenState` orchestration** — adds `_displayZoom`, `_displayLat`, `_displayLng`, `_commandedZoom`, `_animationSettleTimer`. Tap handlers `_onZoomIn` / `_onZoomOut`. State derivers `_zoomInState()` / `_zoomOutState()`.
- **Right-edge button stack** — `RecenterButton` at `bottom: 84`, `ZoomButton(zoomOut)` at `bottom: 144`, `ZoomButton(zoomIn)` at `bottom: 204`, all at `right: 16`.
- **Rename** `_recenterRequestSeq` → `_cameraRequestSeq` since the same monotonic counter now serves both recenter and zoom commands.
- **i18n** — two new ARB keys (`zoomInButtonSemanticLabel`, `zoomOutButtonSemanticLabel`) in `lib/core/i18n/app_en.arb` and `lib/core/i18n/app_tl.arb`.
- **Analytics** — new event `map.zoom.tapped` with `direction: 'in'|'out'` and `from_zoom: int` properties. Routed through the existing `analyticsServiceProvider`.

### Out of scope

- Continuous zoom on press-and-hold (single tap only — matches AC).
- Fractional zoom levels (always integer steps, even if the underlying zoom is fractional after a pinch).
- App-defined zoom bounds tighter than Mapbox's 0–22 — explicitly chosen during brainstorming. A future story can tighten bounds to match the offline tile pack with a one-line change to the disabled-state derivation.
- Pinch-gesture redesign or interception — ACs explicitly require unchanged pinch behavior.
- Refactoring recenter to share more infrastructure beyond what is already shared (`CameraTarget`, `MapRenderer`).
- Polish such as zoom-level indicator overlay or compass — separate stories.

## 3. Architecture

### Files added

```
lib/features/map/presentation/
  zoom_button.dart           # ZoomButton(direction, state, onTap)
  zoom_button_state.dart     # enum: idle | disabled
  zoom_direction.dart        # enum: zoomIn | zoomOut
```

### Files changed

```
lib/features/map/presentation/
  camera_target.dart         # add CameraAnimation enum + animation field
  map_renderer.dart          # MapRenderer.build() gains onCameraChanged param;
                             # MapboxMapRenderer subscribes to native camera-change
                             # listener and forwards (zoom, lat, lng) to widget;
                             # picks easeTo (250ms) vs flyTo (750ms) based on
                             # cameraTarget.animation; FakeMapRenderer adds
                             # _lastOnCameraChanged + simulateCameraChanged()
  map_screen.dart            # _displayZoom/_displayLat/_displayLng,
                             # _commandedZoom, _animationSettleTimer;
                             # _onCameraChanged with rounded-zoom-debounced
                             # setState; _onZoomIn / _onZoomOut handlers;
                             # _zoomInState / _zoomOutState derivers;
                             # mount two ZoomButton instances; rename
                             # _recenterRequestSeq → _cameraRequestSeq;
                             # cancel _animationSettleTimer in dispose
lib/core/i18n/
  app_en.arb, app_tl.arb     # 2 new keys
```

### No changes

- `LocationService`, `AnalyticsService` interface (only a new event name flows through it), Riverpod providers, persistence, Drift schema, `RecenterButton`, the `_onRecenterTap` orchestration.

### Information flow on tap

```
user taps ZoomButton(+)
       ↓
_MapScreenState._onZoomIn()
       ↓
  base = _commandedZoom?.round() ?? _displayZoom?.round()
  if base or _displayLat or _displayLng is null → bail (renderer hasn't
                                                  fired its first
                                                  onCameraChanged yet)
  newZoom = (base + 1).clamp(0, 22)
  if newZoom == base → no-op (defensive; button is already disabled at bound)
       ↓
  analytics.track('map.zoom.tapped', { direction: 'in', from_zoom: base })
       ↓
  setState:
    _commandedZoom = newZoom.toDouble()
    _cameraTarget  = CameraTarget(
      lat: _displayLat,
      lng: _displayLng,
      zoom: newZoom.toDouble(),
      requestId: ++_cameraRequestSeq,
      animation: CameraAnimation.ease,
    )
       ↓
  schedule _animationSettleTimer (350 ms) → if mounted, setState clears _commandedZoom
       ↓
MapboxMapRenderer.didUpdateWidget detects new cameraTarget
       ↓
  _flyToCameraTarget switches on animation:
    ease  → map.easeTo(opts, MapAnimationOptions(duration: 250))
    fly   → map.flyTo (opts, MapAnimationOptions(duration: 750))   ← unchanged for recenter
       ↓
native camera-change listener fires per animation frame
       ↓
  onCameraChanged(zoom, lat, lng) → _displayZoom/Lat/Lng updated
       ↓
  if zoom.round() != prev rounded → setState → disabled state recomputes
```

## 4. Component Contracts

### `ZoomDirection`

```dart
enum ZoomDirection { zoomIn, zoomOut }
```

### `ZoomButtonState`

```dart
enum ZoomButtonState { idle, disabled }
```

### `ZoomButton`

```dart
class ZoomButton extends StatelessWidget {
  const ZoomButton({
    required this.direction,
    required this.state,
    required this.onTap,
    super.key,
  });

  final ZoomDirection direction;
  final ZoomButtonState state;
  final VoidCallback onTap;
}
```

- 48×48 `Material(shape: CircleBorder, color: colors.primary, elevation: 2)`.
- Icon: `Icons.add` for `zoomIn`, `Icons.remove` for `zoomOut`. Color `colors.onPrimary`, size 24.
- `Opacity(0.5)` when `state == disabled`. `InkWell.onTap` is `null` when disabled (no ripple, no callback fired).
- `Semantics(label: zoomInButtonSemanticLabel | zoomOutButtonSemanticLabel, button: true, enabled: state == idle)`.
- Stable widget keys: `Key('map.zoom-in-button')`, `Key('map.zoom-out-button')` for widget tests.

### `CameraAnimation` + `CameraTarget`

```dart
enum CameraAnimation { fly, ease }

class CameraTarget {
  final double lat, lng, zoom;
  final int requestId;
  final CameraAnimation animation;   // NEW, default fly

  const CameraTarget({
    required this.lat,
    required this.lng,
    required this.zoom,
    required this.requestId,
    this.animation = CameraAnimation.fly,
  });

  // Equality: requestId only (existing contract — supersedence dedup).
  // The animation field is renderer metadata, not identity.
}
```

Default `fly` keeps existing recenter call sites and `initialCameraTarget` framing unchanged. Zoom buttons construct with `animation: CameraAnimation.ease`.

### `MapRenderer.build()` signature

```dart
abstract class MapRenderer {
  Widget build(
    BuildContext context, {
    required List<Feature> features,
    required String boundaryGeojson,
    required void Function(Feature) onFeatureTap,
    void Function(double lat, double lng)? onLongPress,
    void Function(double zoom, double lat, double lng)? onCameraChanged,  // NEW
    bool addModeActive,
    CameraTarget? cameraTarget,
    CameraTarget? initialCameraTarget,
  });
}
```

**`MapboxMapRenderer`:**

- In `_onMapCreated`, subscribe to the native camera-change event. On each fire, read `state.cameraState.zoom` and `state.cameraState.center` and forward to `widget.onCameraChanged?.call(zoom, lat, lng)`.
- At the end of `_onMapCreated` (after the existing pending-`cameraTarget` replay block), fire `onCameraChanged` once explicitly with the current camera state. Guarantees the screen has zoom/lat/lng populated by the time the user can interact, so zoom-button taps succeed on the first try.
- Cancel the subscription in `dispose` (or matching teardown — depends on `mapbox_maps_flutter` 2.22 surface; the implementation plan resolves the exact API).
- `_flyToCameraTarget` becomes a switch:
  ```dart
  if (t.animation == CameraAnimation.ease) {
    await map.easeTo(opts, MapAnimationOptions(duration: 250));
  } else {
    await map.flyTo(opts, MapAnimationOptions(duration: 750));
  }
  ```

**`FakeMapRenderer`:**

```dart
void Function(double, double, double)? _lastOnCameraChanged;

Future<void> simulateCameraChanged(double zoom, double lat, double lng) async {
  final cb = _lastOnCameraChanged;
  if (cb != null) cb(zoom, lat, lng);
}
```

Stores the latest callback in `build()`; tests drive the screen's state machine via `simulateCameraChanged`.

### `_MapScreenState` additions

```dart
double? _displayZoom;          // latest from onCameraChanged (live)
double? _displayLat;
double? _displayLng;
double? _commandedZoom;        // last value WE issued; null when settled
Timer?  _animationSettleTimer;

// _recenterRequestSeq is renamed to _cameraRequestSeq.

void _onCameraChanged(double zoom, double lat, double lng);
Future<void> _onZoomIn();
Future<void> _onZoomOut();
ZoomButtonState _zoomInState();
ZoomButtonState _zoomOutState();
```

## 5. Orchestration & Edge Cases

### Tap handler (zoom-in; mirrored for zoom-out)

```dart
Future<void> _onZoomIn() async {
  // Anchor on commanded if animating, display if known. Bail out if
  // neither is set — only possible in the millisecond window between
  // renderer mount and the first onCameraChanged fire (see Renderer
  // contract below). The user's next tap will succeed.
  final base = _commandedZoom?.round() ?? _displayZoom?.round();
  if (base == null) return;
  final lat = _displayLat;
  final lng = _displayLng;
  if (lat == null || lng == null) return;  // same race; same bail

  final newZoom = (base + 1).clamp(0, 22);
  if (newZoom == base) return;  // already at ceiling — defensive

  ref.read(analyticsServiceProvider).track(
    'map.zoom.tapped',
    properties: {'direction': 'in', 'from_zoom': base},
  );

  setState(() {
    _commandedZoom = newZoom.toDouble();
    _cameraTarget = CameraTarget(
      lat: lat,
      lng: lng,
      zoom: newZoom.toDouble(),
      requestId: ++_cameraRequestSeq,
      animation: CameraAnimation.ease,
    );
  });

  _animationSettleTimer?.cancel();
  _animationSettleTimer = Timer(const Duration(milliseconds: 350), () {
    if (mounted) setState(() => _commandedZoom = null);
  });
}
```

### Renderer contract — initial camera-change

`MapboxMapRenderer` MUST fire `onCameraChanged` at least once shortly after the map is ready, with the current camera state. This makes the "tap before any animation/pinch happened" case work without an awkward fallback in the screen. The natural place is at the end of `_onMapCreated`, after the existing `cameraTarget` replay block:

```dart
final state = await map.getCameraState();
widget.onCameraChanged?.call(
  state.zoom,
  state.center.coordinates.lat.toDouble(),
  state.center.coordinates.lng.toDouble(),
);
```

`FakeMapRenderer` does not need to satisfy this contract automatically — widget tests drive `simulateCameraChanged` explicitly to position the screen for each scenario.

### Camera-change listener

```dart
void _onCameraChanged(double zoom, double lat, double lng) {
  final prevRounded = _displayZoom?.round();
  _displayZoom = zoom;
  _displayLat = lat;
  _displayLng = lng;
  if (prevRounded != zoom.round()) {
    setState(() {});  // disabled state may have flipped
  }
}
```

Debounced to setState only when the rounded zoom changes — avoids per-frame rebuilds during a 60 fps animation.

### Disabled-state derivation

```dart
ZoomButtonState _zoomInState() {
  final z = _commandedZoom ?? _displayZoom?.round();
  if (z == null) return ZoomButtonState.idle;
  return z >= 22 ? ZoomButtonState.disabled : ZoomButtonState.idle;
}

ZoomButtonState _zoomOutState() {
  final z = _commandedZoom ?? _displayZoom?.round();
  if (z == null) return ZoomButtonState.idle;
  return z <= 0 ? ZoomButtonState.disabled : ZoomButtonState.idle;
}
```

Until the renderer reports the first zoom, both buttons are idle. A brief window where rapid taps could over-shoot the bound is acceptable: `initialCameraTarget` puts the user in normal field range (~zoom 14–17), nowhere near 0 or 22.

### Edge cases

| Case | Behavior |
|---|---|
| **Cold start, first tap before `onCameraChanged` fires** | Renderer fires `onCameraChanged` once at the end of `_onMapCreated` (see §4 renderer contract). The window in which the user can tap before that fire is sub-frame; if it does happen, the tap handler bails cleanly and the next tap succeeds. |
| **Rapid taps during ease animation** | `_commandedZoom` accumulates — 3 taps from 14 reliably reach 17. Each tap pushes a new `CameraTarget` with new `requestId`; renderer's `didUpdateWidget` calls `easeTo` again, smoothly redirecting from the current animated position. |
| **User pinches mid-animation** | Mapbox cancels our `easeTo` when pinch starts. `onCameraChanged` keeps firing through the pinch. After the 350 ms settle timer, `_commandedZoom` clears, so the next tap re-anchors on the pinch's resting zoom. |
| **User taps + at zoom 21.6 (mid-pinch)** | `base = 21.6.round() = 22`. `newZoom = clamp(23, 0, 22) = 22 = base` → no-op. Button has just disabled itself this frame. |
| **Recenter in flight, user taps zoom** | Recenter pushes a `fly`-animation target; zoom tap pushes an `ease`-animation target with new `requestId`. The new target supersedes; recenter's intended zoom (17) is overridden. Acceptable — most recent intent wins. |
| **Min/max never reachable in practice** | Mapbox 0–22 means disabled state is mostly theoretical. Logic is wired so a future tighter bound is a one-line change in `_zoomInState` / `_zoomOutState`. |
| **`dispose`** | Cancel `_animationSettleTimer` to prevent setState-after-dispose. |

### Why no `loading` state

Recenter has `loading` because it awaits a GPS fix. Zoom is pure camera math against the existing render — there is nothing async to wait for from the user's perspective. Taps fire-and-forget; the visual feedback IS the camera animation.

## 6. Testing

### Unit tests

**`camera_target_test.dart`** — extend existing test:

- `CameraTarget` defaults to `CameraAnimation.fly` when `animation` is omitted (back-compat).
- Equality remains `requestId`-only — two targets with the same `requestId` but different `animation` values are still equal. Documents that the existing equality contract is unaffected.

`ZoomButtonState` and `ZoomDirection` are pure enums — no unit tests.

### Widget tests — `zoom_button_test.dart`

Mirrors `recenter_button_test.dart`. Each `(direction, state)` combination:

1. **`zoomIn` + `idle`** → `Icons.add` rendered, `onTap` fires, `Semantics(enabled: true)`, opacity 1.0.
2. **`zoomOut` + `idle`** → `Icons.remove` rendered, `onTap` fires, opacity 1.0.
3. **`zoomIn` + `disabled`** → `onTap` does NOT fire, opacity 0.5, `Semantics(enabled: false)`.
4. **`zoomOut` + `disabled`** → same as #3 with `Icons.remove`.

### Widget tests — `map_screen_test.dart` additions

Use the existing `FakeMapRenderer` test seam; override `mapRendererProvider` and seed an assignment + features as the recenter tests do.

1. **AC1 — buttons mount.** Both `Key('map.zoom-in-button')` and `Key('map.zoom-out-button')` are findable.
2. **AC2 — tap zoom-in pushes ease target.** Renderer mounts; `simulateCameraChanged(15.0, lat, lng)`. Tap zoom-in. Assert `fakeRenderer.lastCameraTarget.zoom == 16` and `animation == CameraAnimation.ease`.
3. **AC3 — tap zoom-out.** Mirror of #2; expected zoom 14.
4. **AC4 — disabled at max.** `simulateCameraChanged(22.0, lat, lng)`. Pump. Tap zoom-in. Assert `cameraTargetHistory.length` unchanged AND the button's `Semantics(enabled: false)`.
5. **AC5 — disabled at min.** Mirror of #4 at zoom 0.
6. **AC6 — pinch flips disabled state.** Start at 15. Both idle. `simulateCameraChanged(22.0, ...)`. Pump. Zoom-in becomes disabled.
7. **Rapid taps accumulate.** Tap zoom-in three times before settle timer fires. Assert latest `cameraTarget.zoom == startZoom + 3`. Verifies `_commandedZoom` anchoring.
8. **Settle timer drops `_commandedZoom`.** Tap once at zoom 15 → target 16. `simulateCameraChanged(20.0, ...)`. `pump(Duration(milliseconds: 400))` to fire settle timer. Tap zoom-in → next target is 21 (anchored on display, not stale commanded).
9. **Recenter unaffected.** Existing recenter test passes; its `CameraTarget` has `animation: fly` (default).
10. **Analytics fires.** Override `analyticsServiceProvider` with `RecordingAnalyticsService`. Tap zoom-in. Assert one `'map.zoom.tapped'` event with `direction: 'in'` and an integer `from_zoom`.

### Manual happy path (in implementation plan)

Open the map on a real device → see assignment framed → pinch to ~zoom 19 → tap **−** three times → camera eases by ~1 each tap visibly → tap **−** until disabled near 0 → tap **+** until disabled near 22 → tap recenter → camera flies (slower) to GPS at zoom 17 → both zoom buttons re-enable. Verify no console warnings and analytics emits one `map.zoom.tapped` per tap.

### What's NOT covered at the widget layer

- Real `MapboxMapRenderer.easeTo` — Mapbox does not render in `flutter_tester`, same constraint as recenter. Manual happy path covers it.
- The native camera-change subscription itself — covered by manual happy path. `FakeMapRenderer` exercises the contract from the screen's side.

## 7. i18n

Two new ARB keys in `lib/core/i18n/app_en.arb`:

```json
"zoomInButtonSemanticLabel": "Zoom in",
"zoomOutButtonSemanticLabel": "Zoom out",
```

Mirrored in `lib/core/i18n/app_tl.arb` with TL pending translation (per project convention; the recenter PR merged with TL pending).

## 8. Analytics

One new event:

- **`map.zoom.tapped`** — properties `{direction: 'in'|'out', from_zoom: int}`. Routed through `analyticsServiceProvider`. In debug builds the `ConsoleAnalyticsService` prints; in release the `NoopAnalyticsService` swallows.

Mirrors the recenter event's shape (`map.recenter.tapped`).

## 9. Acceptance Criteria → Implementation Mapping

| AC | Implemented by |
|---|---|
| AC1: buttons visible as persistent overlays | Two `Positioned` `ZoomButton` instances mounted in the `Stack` in `map_screen.dart` |
| AC2: tap zoom-in increments by 1 zoom level | `_onZoomIn` → `CameraTarget(zoom: base+1, animation: ease)` → `MapboxMapRenderer.easeTo` |
| AC3: tap zoom-out decrements by 1 zoom level | `_onZoomOut` (mirror of AC2) |
| AC4: disabled at max zoom | `_zoomInState()` returns `disabled` when effective zoom ≥ 22; `ZoomButton` opacity 0.5 + null `onTap` |
| AC5: disabled at min zoom | `_zoomOutState()` returns `disabled` when effective zoom ≤ 0 (mirror of AC4) |
| AC6: pinch continues to work without interference | No pinch-related code changes. Pinch updates `_displayZoom` via the same `onCameraChanged` callback that drives disabled state, so pinch and buttons stay in sync. |

## 10. Open Questions

None remaining for v1. Items deferred to future stories:

- App-defined zoom bounds matched to the offline tile pack — out of scope per clarifying.
- Zoom-level indicator overlay — out of scope (separate UX story).
- Press-and-hold continuous zoom — out of scope per AC ("tap").
