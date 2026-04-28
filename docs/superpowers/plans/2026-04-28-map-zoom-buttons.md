# Map Zoom Buttons — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add stacked zoom-in / zoom-out circular buttons above the existing recenter button on the map screen. Each tap eases the camera ±1 zoom level over ~250 ms, anchored on the current map center; buttons disable at the Mapbox style's bounds (0 / 22); pinch gestures continue to work and update disabled state in real time.

**Architecture:** `ZoomButton` is a pure-UI `StatelessWidget` mirroring `RecenterButton`'s 48×48 circle. Tap orchestration (`_onZoomIn` / `_onZoomOut`) lives on `_MapScreenState` and pushes a `CameraTarget` with a new `CameraAnimation.ease` field; `MapboxMapRenderer` switches between `easeTo` (250 ms) and `flyTo` (750 ms) based on this field. The screen tracks current zoom/center via a new `MapRenderer.onCameraChanged` callback so disabled state remains correct even after pinch. Rapid taps anchor on a `_commandedZoom` field (cleared by a 350 ms settle timer) so 3 fast taps from zoom 14 reliably reach 17.

**Tech Stack:** Flutter 3.22 / Dart 3.4+, `mapbox_maps_flutter ^2.5` (resolved 2.22), `flutter_riverpod ^2.5`, manual `Provider<>(...)` syntax (no codegen), `flutter_test`, ARB-based i18n via `flutter_localizations` (arb dir `lib/core/i18n/`).

**Spec:** `docs/superpowers/specs/2026-04-28-map-zoom-buttons-design.md`

---

## File structure

### Files to create

| Path | Responsibility |
|---|---|
| `lib/features/map/presentation/zoom_direction.dart` | `enum ZoomDirection { zoomIn, zoomOut }` |
| `lib/features/map/presentation/zoom_button_state.dart` | `enum ZoomButtonState { idle, disabled }` |
| `lib/features/map/presentation/zoom_button.dart` | Pure-UI `StatelessWidget` consuming `ZoomDirection` + `ZoomButtonState` + `onTap` |
| `test/features/map/zoom_button_test.dart` | Pure-widget tests for the button (4 cases) |
| `test/features/map/map_screen_zoom_test.dart` | Widget tests for `_onZoomIn` / `_onZoomOut` orchestration |

### Files to modify

| Path | Change |
|---|---|
| `lib/features/map/presentation/camera_target.dart` | Add `enum CameraAnimation { fly, ease }` and `final CameraAnimation animation` field on `CameraTarget` (default `fly`). Equality remains `requestId`-only |
| `test/features/map/camera_target_test.dart` | Add tests: default animation is `fly`; equality ignores animation field |
| `lib/features/map/presentation/map_renderer.dart` | `MapRenderer.build()` gains `void Function(double zoom, double lat, double lng)? onCameraChanged`. `FakeMapRenderer` stores callback + adds `simulateCameraChanged`. `_MapboxMapView` passes `onCameraChangeListener` to `MapWidget`, fires initial onCameraChanged at end of `_onMapCreated`, and switches `easeTo`/`flyTo` based on `cameraTarget.animation` |
| `lib/features/map/presentation/map_screen.dart` | Add `_displayZoom`, `_displayLat`, `_displayLng`, `_commandedZoom`, `_animationSettleTimer`. Rename `_recenterRequestSeq` → `_cameraRequestSeq`. Add `_onCameraChanged`, `_onZoomIn`, `_onZoomOut`, `_zoomInState`, `_zoomOutState`. Pass `onCameraChanged` to renderer. Mount two `ZoomButton` instances at `right: 16, bottom: 144` (out) and `right: 16, bottom: 204` (in). Cancel timer in `dispose` |
| `lib/core/i18n/app_en.arb` | Add `zoomInButtonSemanticLabel` and `zoomOutButtonSemanticLabel` |
| `lib/core/i18n/app_tl.arb` | Mirror the 2 keys (English fallback; project convention is to ship TL pending) |

### Files NOT modified

- `lib/features/map/presentation/recenter_button.dart`, `recenter_button_state.dart` — untouched.
- `lib/core/location/*`, `lib/core/analytics/*`, Riverpod providers, persistence layer — untouched.
- `_onRecenterTap` orchestration — untouched (its `CameraTarget` uses `animation: fly` by default).

---

## Task ordering rationale

1. **Foundations (1–3):** `CameraAnimation` enum + `CameraTarget` extension, the two new enums, and i18n keys. Pure additions with no dependents yet — safe to land independently.
2. **Leaf widget (4):** `ZoomButton` is pure UI; tested without orchestration.
3. **Renderer plumbing (5):** `MapRenderer.onCameraChanged` + animation-aware fly/ease in the real renderer + `simulateCameraChanged` test seam in the fake. New param is optional with default `null`, so existing call sites compile unchanged.
4. **Mount + tap handlers (6):** Wire up `_displayZoom/Lat/Lng` tracking and `_onZoomIn` / `_onZoomOut`. Covers AC1, AC2, AC3.
5. **Disabled-state derivation (7):** `_zoomInState` / `_zoomOutState` close AC4, AC5, AC6 (pinch reactivity falls out for free since the same `_displayZoom` feeds disabled state).
6. **Rapid-tap accumulation (8):** `_commandedZoom` + 350 ms settle timer.
7. **Analytics (9):** `map.zoom.tapped` event with `direction` + `from_zoom`.
8. **Final regression (10):** `flutter analyze`, full test suite, manual QA.

---

## Task 1: Extend `CameraTarget` with `CameraAnimation`

**Files:**
- Modify: `lib/features/map/presentation/camera_target.dart`
- Modify: `test/features/map/camera_target_test.dart`

- [ ] **Step 1: Write the failing tests**

Replace the contents of `test/features/map/camera_target_test.dart` with:

```dart
import 'package:firecheck/features/map/presentation/camera_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('equality is by requestId only', () {
    const a = CameraTarget(lat: 10, lng: 123, zoom: 17, requestId: 1);
    const b = CameraTarget(lat: 99, lng: 99, zoom: 5, requestId: 1);
    const c = CameraTarget(lat: 10, lng: 123, zoom: 17, requestId: 2);

    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });

  test('default animation is fly (recenter back-compat)', () {
    const t = CameraTarget(lat: 10, lng: 123, zoom: 17, requestId: 1);
    expect(t.animation, CameraAnimation.fly);
  });

  test('animation field does not affect equality', () {
    const a = CameraTarget(
      lat: 10, lng: 123, zoom: 17, requestId: 1,
      animation: CameraAnimation.fly,
    );
    const b = CameraTarget(
      lat: 10, lng: 123, zoom: 17, requestId: 1,
      animation: CameraAnimation.ease,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

```bash
flutter test test/features/map/camera_target_test.dart
```

Expected: compile error / test failure complaining about `CameraAnimation` undefined and the `animation:` named parameter not existing.

- [ ] **Step 3: Implement the change**

Replace the contents of `lib/features/map/presentation/camera_target.dart` with:

```dart
import 'package:flutter/foundation.dart';

/// Animation style for a camera command.
///
/// `fly` — Mapbox `flyTo` (~750 ms); a cinematic zoom-out-and-in arc, used
/// for cross-screen jumps like recenter-to-GPS.
/// `ease` — Mapbox `easeTo` (~250 ms); a smooth direct interpolation, used
/// for ±1 zoom steps from the explicit zoom buttons.
enum CameraAnimation { fly, ease }

/// A camera-fly request from the screen to the renderer.
///
/// Equality is on [requestId] only so two taps producing identical
/// coordinates still trigger a fresh fly: the renderer's didUpdateWidget
/// detects "different requestId" → flyTo. This is intentional — without it,
/// repeat taps at the same position would be no-ops.
///
/// [animation] is renderer metadata, not identity — two targets with the
/// same `requestId` but different `animation` values are still equal.
@immutable
class CameraTarget {
  const CameraTarget({
    required this.lat,
    required this.lng,
    required this.zoom,
    required this.requestId,
    this.animation = CameraAnimation.fly,
  });

  final double lat;
  final double lng;
  final double zoom;
  final int requestId;
  final CameraAnimation animation;

  @override
  bool operator ==(Object other) =>
      other is CameraTarget && other.requestId == requestId;

  @override
  int get hashCode => requestId.hashCode;
}
```

- [ ] **Step 4: Run the tests again**

```bash
flutter test test/features/map/camera_target_test.dart
```

Expected: all 3 tests pass.

- [ ] **Step 5: Confirm the rest of the suite still compiles**

```bash
flutter analyze
```

Expected: no new errors. (Existing `CameraTarget(...)` call sites in `map_screen.dart` and tests use only the four required parameters; the new optional `animation` defaults to `fly`.)

- [ ] **Step 6: Commit**

```bash
git add lib/features/map/presentation/camera_target.dart test/features/map/camera_target_test.dart
git commit -m "feat(map): add CameraAnimation enum to CameraTarget (default fly)"
```

---

## Task 2: Add `ZoomDirection` and `ZoomButtonState` enums

**Files:**
- Create: `lib/features/map/presentation/zoom_direction.dart`
- Create: `lib/features/map/presentation/zoom_button_state.dart`

(Both are pure enums. Follows the precedent set by `recenter_button_state.dart` — no unit test.)

- [ ] **Step 1: Create `zoom_direction.dart`**

```dart
enum ZoomDirection { zoomIn, zoomOut }
```

- [ ] **Step 2: Create `zoom_button_state.dart`**

```dart
enum ZoomButtonState { idle, disabled }
```

- [ ] **Step 3: Confirm analyzer is clean**

```bash
flutter analyze
```

Expected: no errors / warnings.

- [ ] **Step 4: Commit**

```bash
git add lib/features/map/presentation/zoom_direction.dart lib/features/map/presentation/zoom_button_state.dart
git commit -m "feat(map): add ZoomDirection and ZoomButtonState enums"
```

---

## Task 3: Add i18n keys

**Files:**
- Modify: `lib/core/i18n/app_en.arb`
- Modify: `lib/core/i18n/app_tl.arb`

- [ ] **Step 1: Add the two keys to `app_en.arb`**

Open `lib/core/i18n/app_en.arb`. Just before the closing `}` (after `locationSnackbarLowAccuracy`), add:

```json
  "zoomInButtonSemanticLabel": "Zoom in",
  "zoomOutButtonSemanticLabel": "Zoom out"
```

Make sure the line BEFORE these two new entries ends with a comma. Final block in the file should look like:

```json
  "locationSnackbarLowAccuracy": "Location accuracy is low. Showing your approximate position.",
  "zoomInButtonSemanticLabel": "Zoom in",
  "zoomOutButtonSemanticLabel": "Zoom out"
}
```

- [ ] **Step 2: Mirror the two keys in `app_tl.arb`**

Open `lib/core/i18n/app_tl.arb`. Add the same keys at the same location, with English fallback values (project convention from US-12: `recenterButtonSemanticLabel` and friends shipped TL pending; a translator pass closes them later).

```json
  "zoomInButtonSemanticLabel": "Zoom in",
  "zoomOutButtonSemanticLabel": "Zoom out"
```

- [ ] **Step 3: Regenerate the localization classes**

```bash
flutter gen-l10n
```

Expected output: regenerates `lib/generated/l10n/app_localizations*.dart`. No errors.

- [ ] **Step 4: Confirm the keys are accessible from generated code**

```bash
grep -E "zoomInButtonSemanticLabel|zoomOutButtonSemanticLabel" lib/generated/l10n/app_localizations*.dart
```

Expected: at least 4 matches (getter declarations + their EN/TL implementations).

- [ ] **Step 5: Commit**

```bash
git add lib/core/i18n/app_en.arb lib/core/i18n/app_tl.arb lib/generated/l10n/
git commit -m "i18n(map): add zoom button semantic labels (TL pending translation)"
```

---

## Task 4: `ZoomButton` widget (TDD)

**Files:**
- Create: `test/features/map/zoom_button_test.dart`
- Create: `lib/features/map/presentation/zoom_button.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/features/map/zoom_button_test.dart`:

```dart
import 'package:firecheck/features/map/presentation/zoom_button.dart';
import 'package:firecheck/features/map/presentation/zoom_button_state.dart';
import 'package:firecheck/features/map/presentation/zoom_direction.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),);
    await tester.pump();
  }

  group('ZoomButton', () {
    testWidgets('zoomIn idle: renders + icon and tap invokes onTap',
        (tester) async {
      var taps = 0;
      await pump(
        tester,
        ZoomButton(
          direction: ZoomDirection.zoomIn,
          state: ZoomButtonState.idle,
          onTap: () => taps++,
        ),
      );
      expect(find.byIcon(Icons.add), findsOneWidget);

      await tester.tap(find.byType(ZoomButton));
      expect(taps, 1);
    });

    testWidgets('zoomOut idle: renders − icon and tap invokes onTap',
        (tester) async {
      var taps = 0;
      await pump(
        tester,
        ZoomButton(
          direction: ZoomDirection.zoomOut,
          state: ZoomButtonState.idle,
          onTap: () => taps++,
        ),
      );
      expect(find.byIcon(Icons.remove), findsOneWidget);

      await tester.tap(find.byType(ZoomButton));
      expect(taps, 1);
    });

    testWidgets('zoomIn disabled: opacity 0.5, taps do NOT invoke onTap',
        (tester) async {
      var taps = 0;
      await pump(
        tester,
        ZoomButton(
          direction: ZoomDirection.zoomIn,
          state: ZoomButtonState.disabled,
          onTap: () => taps++,
        ),
      );

      final opacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.byIcon(Icons.add),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 0.5);

      await tester.tap(find.byType(ZoomButton), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('zoomOut disabled: opacity 0.5, taps do NOT invoke onTap',
        (tester) async {
      var taps = 0;
      await pump(
        tester,
        ZoomButton(
          direction: ZoomDirection.zoomOut,
          state: ZoomButtonState.disabled,
          onTap: () => taps++,
        ),
      );

      final opacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.byIcon(Icons.remove),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 0.5);

      await tester.tap(find.byType(ZoomButton), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('semantic labels: Zoom in / Zoom out', (tester) async {
      await pump(
        tester,
        ZoomButton(
          direction: ZoomDirection.zoomIn,
          state: ZoomButtonState.idle,
          onTap: () {},
        ),
      );
      expect(find.bySemanticsLabel('Zoom in'), findsOneWidget);

      await pump(
        tester,
        ZoomButton(
          direction: ZoomDirection.zoomOut,
          state: ZoomButtonState.idle,
          onTap: () {},
        ),
      );
      expect(find.bySemanticsLabel('Zoom out'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

```bash
flutter test test/features/map/zoom_button_test.dart
```

Expected: compile error — `zoom_button.dart` does not exist yet.

- [ ] **Step 3: Implement the widget**

Create `lib/features/map/presentation/zoom_button.dart`:

```dart
import 'package:firecheck/features/map/presentation/zoom_button_state.dart';
import 'package:firecheck/features/map/presentation/zoom_direction.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final isDisabled = state == ZoomButtonState.disabled;
    final isInteractive = !isDisabled;

    final icon = direction == ZoomDirection.zoomIn ? Icons.add : Icons.remove;
    final label = direction == ZoomDirection.zoomIn
        ? l.zoomInButtonSemanticLabel
        : l.zoomOutButtonSemanticLabel;

    final child = SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: colors.primary,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: isInteractive ? onTap : null,
          child: Center(
            child: Icon(icon, color: colors.onPrimary, size: 24),
          ),
        ),
      ),
    );

    return Semantics(
      label: label,
      button: true,
      enabled: isInteractive,
      child: Opacity(opacity: isDisabled ? 0.5 : 1.0, child: child),
    );
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

```bash
flutter test test/features/map/zoom_button_test.dart
```

Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/map/presentation/zoom_button.dart test/features/map/zoom_button_test.dart
git commit -m "feat(map): add ZoomButton widget (idle/disabled, +/- icons)"
```

---

## Task 5: `MapRenderer.onCameraChanged` + animation-aware fly/ease

**Files:**
- Modify: `lib/features/map/presentation/map_renderer.dart`

This task changes the `MapRenderer.build()` interface, so any caller that currently passes positional arguments must be checked. Today there is exactly one caller (`map_screen.dart`) and it passes only named arguments — adding a new optional named param `onCameraChanged` is non-breaking.

- [ ] **Step 1: Update the abstract interface**

In `lib/features/map/presentation/map_renderer.dart`, replace the `MapRenderer` abstract class with:

```dart
/// Minimal surface the map screen actually needs. Lets tests substitute a
/// renderer that doesn't require a GL context.
// ignore: one_member_abstracts
abstract class MapRenderer {
  Widget build(
    BuildContext context, {
    required List<Feature> features,
    required String boundaryGeojson,
    required void Function(Feature) onFeatureTap,
    void Function(double lat, double lng)? onLongPress,
    void Function(double zoom, double lat, double lng)? onCameraChanged,
    bool addModeActive,
    CameraTarget? cameraTarget,
    CameraTarget? initialCameraTarget,
  });
}
```

- [ ] **Step 2: Update `FakeMapRenderer` to record the callback and expose `simulateCameraChanged`**

Still in `lib/features/map/presentation/map_renderer.dart`, replace the `FakeMapRenderer` class with:

```dart
/// Fake for widget tests — renders one tappable tile per feature instead of
/// a real map. Matches the real renderer's tap contract.
class FakeMapRenderer implements MapRenderer {
  void Function(double, double)? _lastOnLongPress;
  void Function(double, double, double)? _lastOnCameraChanged;
  CameraTarget? lastCameraTarget;
  CameraTarget? lastInitialCameraTarget;
  final List<CameraTarget> cameraTargetHistory = [];

  /// Test seam: simulates a long-press at the given coordinates. Invokes the
  /// most recently stored onLongPress callback; no-op if none was provided.
  Future<void> simulateLongPress(double lat, double lng) async {
    final cb = _lastOnLongPress;
    if (cb != null) cb(lat, lng);
  }

  /// Test seam: simulates a camera-change event from the underlying map.
  /// Invokes the most recently stored onCameraChanged callback; no-op if
  /// none was provided.
  Future<void> simulateCameraChanged(double zoom, double lat, double lng) async {
    final cb = _lastOnCameraChanged;
    if (cb != null) cb(zoom, lat, lng);
  }

  @override
  Widget build(
    BuildContext context, {
    required List<Feature> features,
    required String boundaryGeojson,
    required void Function(Feature) onFeatureTap,
    void Function(double lat, double lng)? onLongPress,
    void Function(double zoom, double lat, double lng)? onCameraChanged,
    bool addModeActive = false,
    CameraTarget? cameraTarget,
    CameraTarget? initialCameraTarget,
  }) {
    _lastOnLongPress = onLongPress;
    _lastOnCameraChanged = onCameraChanged;
    lastInitialCameraTarget = initialCameraTarget;
    if (cameraTarget != null && cameraTarget != lastCameraTarget) {
      cameraTargetHistory.add(cameraTarget);
    }
    lastCameraTarget = cameraTarget;
    return ListView(
      shrinkWrap: true,
      children: [
        if (addModeActive)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('add-mode'),
          ),
        ...features.map((f) {
          return GestureDetector(
            key: Key('fake-map-feature-${f.id}'),
            onTap: () => onFeatureTap(f),
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

  Color _colorForStatus(String status) {
    switch (status) {
      case 'complete':
        return const Color(0x66276749);
      case 'in_progress':
        return const Color(0x66B7791F);
      default:
        return const Color(0x66C53030);
    }
  }
}
```

- [ ] **Step 3: Update `MapboxMapRenderer.build` to pass the callback through**

In the same file, replace the `MapboxMapRenderer.build` method with:

```dart
class MapboxMapRenderer implements MapRenderer {
  @override
  Widget build(
    BuildContext context, {
    required List<Feature> features,
    required String boundaryGeojson,
    required void Function(Feature) onFeatureTap,
    void Function(double lat, double lng)? onLongPress,
    void Function(double zoom, double lat, double lng)? onCameraChanged,
    bool addModeActive = false,
    CameraTarget? cameraTarget,
    CameraTarget? initialCameraTarget,
  }) {
    return _MapboxMapView(
      features: features,
      boundaryGeojson: boundaryGeojson,
      onFeatureTap: onFeatureTap,
      onLongPress: onLongPress,
      onCameraChanged: onCameraChanged,
      addModeActive: addModeActive,
      cameraTarget: cameraTarget,
      initialCameraTarget: initialCameraTarget,
    );
  }
}
```

- [ ] **Step 4: Add the field + constructor param to `_MapboxMapView`**

Replace the `_MapboxMapView` declaration block (the StatefulWidget — lines starting `class _MapboxMapView extends StatefulWidget`) with:

```dart
class _MapboxMapView extends StatefulWidget {
  const _MapboxMapView({
    required this.features,
    required this.boundaryGeojson,
    required this.onFeatureTap,
    this.onLongPress,
    this.onCameraChanged,
    this.addModeActive = false,
    this.cameraTarget,
    this.initialCameraTarget,
  });

  final List<Feature> features;
  final String boundaryGeojson;
  final void Function(Feature) onFeatureTap;
  final void Function(double lat, double lng)? onLongPress;
  final void Function(double zoom, double lat, double lng)? onCameraChanged;
  final bool addModeActive;
  final CameraTarget? cameraTarget;
  final CameraTarget? initialCameraTarget;

  @override
  State<_MapboxMapView> createState() => _MapboxMapViewState();
}
```

- [ ] **Step 5: Wire `onCameraChangeListener` into `MapWidget` and switch easeTo/flyTo on animation**

Still in `_MapboxMapView`, update the `build` method to pass the camera-change listener to `MapWidget`. Replace the existing `MapWidget(...)` return block (currently in `build`) with:

```dart
@override
Widget build(BuildContext context) {
  final initial = widget.initialCameraTarget;
  return MapWidget(
    cameraOptions: CameraOptions(
      center: initial != null
          ? Point(coordinates: Position(initial.lng, initial.lat))
          : Point(coordinates: Position(123.88270, 10.31810)),
      zoom: initial?.zoom ?? 15,
    ),
    // Without an explicit styleUri the map renders a black background
    // because no style is loaded. Streets v12 is the Phase 1 spec choice.
    styleUri: 'mapbox://styles/mapbox/streets-v12',
    onMapCreated: _onMapCreated,
    onLongTapListener: (MapContentGestureContext ctx) {
      if (widget.addModeActive && widget.onLongPress != null) {
        final pos = ctx.point.coordinates;
        widget.onLongPress!(pos.lat.toDouble(), pos.lng.toDouble());
      }
    },
    onCameraChangeListener: (CameraChangedEventData data) {
      final cb = widget.onCameraChanged;
      if (cb == null) return;
      final state = data.cameraState;
      cb(
        state.zoom,
        state.center.coordinates.lat.toDouble(),
        state.center.coordinates.lng.toDouble(),
      );
    },
  );
}
```

- [ ] **Step 6: Update `_flyToCameraTarget` to pick easeTo vs flyTo from `animation`**

Still in `_MapboxMapViewState`, replace the `_flyToCameraTarget` method with:

```dart
Future<void> _flyToCameraTarget(CameraTarget t) async {
  final map = _mapboxMap;
  if (map == null) return; // _onMapCreated hasn't run yet
  final opts = CameraOptions(
    center: Point(coordinates: Position(t.lng, t.lat)),
    zoom: t.zoom,
  );
  if (t.animation == CameraAnimation.ease) {
    await map.easeTo(opts, MapAnimationOptions(duration: 250));
  } else {
    await map.flyTo(opts, MapAnimationOptions(duration: 750));
  }
}
```

(`CameraAnimation` is already exported from `camera_target.dart`, which is imported at the top of `map_renderer.dart`.)

- [ ] **Step 7: Fire onCameraChanged once at end of `_onMapCreated`**

In the same file's `_onMapCreated` method, append the following block at the very end (after the existing pending-`cameraTarget` replay block):

```dart
// Guarantee the screen has at least one zoom/center sample by the time
// the user can interact. Without this, zoom-button taps in the first
// few frames bail out (no _displayZoom yet) — see US-13 spec §5.
final initialState = await map.getCameraState();
widget.onCameraChanged?.call(
  initialState.zoom,
  initialState.center.coordinates.lat.toDouble(),
  initialState.center.coordinates.lng.toDouble(),
);
```

- [ ] **Step 8: Run the existing test suite to confirm nothing regressed**

```bash
flutter analyze
flutter test test/features/map/
```

Expected: analyzer clean, all map tests still pass. The new `onCameraChanged` param is optional and `null` by default, so existing test setups (which don't pass it) compile and behave unchanged.

- [ ] **Step 9: Commit**

```bash
git add lib/features/map/presentation/map_renderer.dart
git commit -m "feat(map): MapRenderer.onCameraChanged + animation-aware fly/ease"
```

---

## Task 6: Mount `ZoomButton`s + `_displayZoom` tracking + tap handlers (AC1, AC2, AC3)

**Files:**
- Modify: `lib/features/map/presentation/map_screen.dart`
- Create: `test/features/map/map_screen_zoom_test.dart`

This task adds the smallest viable orchestration: `_displayZoom/Lat/Lng` tracking, `_onZoomIn` / `_onZoomOut` handlers (no disabled-state derivation yet — buttons stay `idle`), and mounts the two buttons. Covers AC1 (buttons visible), AC2 (zoom-in pushes ease target), AC3 (zoom-out pushes ease target).

- [ ] **Step 1: Write the failing tests**

Create `test/features/map/map_screen_zoom_test.dart`:

```dart
import 'package:firecheck/core/analytics/analytics_providers.dart';
import 'package:firecheck/core/analytics/analytics_service.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/location/location_providers.dart';
import 'package:firecheck/core/location/location_service.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/map/presentation/camera_target.dart';
import 'package:firecheck/features/map/presentation/map_providers.dart';
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:firecheck/features/map/presentation/map_screen.dart';
import 'package:firecheck/features/map/presentation/zoom_button.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

Assignment fakeAssignment() => Assignment(
      id: 'a1',
      enumeratorId: 'e@example.com',
      campaignId: 'c1',
      boundaryPolygonGeojson:
          '{"type":"Polygon","coordinates":[[[123.882,10.317],'
          '[123.884,10.317],[123.884,10.319],'
          '[123.882,10.319],[123.882,10.317]]]}',
      status: 'assigned',
      closedRemotely: false,
      createdAt: DateTime(2026),
    );

Future<void> pumpMap(
  WidgetTester tester, {
  required FakeMapRenderer renderer,
  AnalyticsService? analytics,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mapRendererProvider.overrideWithValue(renderer),
      locationServiceProvider.overrideWithValue(FakeLocationService()),
      if (analytics != null)
        analyticsServiceProvider.overrideWithValue(analytics),
      currentFeaturesProvider.overrideWith((_) => Stream.value(const [])),
      currentAssignmentProvider.overrideWith((_) => Stream.value(fakeAssignment())),
      assignmentLockStateProvider.overrideWith((_) => Stream.value(const Unlocked())),
      currentPositionProvider.overrideWith((_) => const Stream<Position>.empty()),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MapScreen(),
    ),
  ),);
  await tester.pump();
  await tester.pump();
}

void main() {
  group('US-13 zoom buttons — mount + tap handlers', () {
    testWidgets('AC1: both zoom-in and zoom-out buttons mount', (tester) async {
      final renderer = FakeMapRenderer();
      await pumpMap(tester, renderer: renderer);

      expect(find.byKey(const Key('map.zoom-in-button')), findsOneWidget);
      expect(find.byKey(const Key('map.zoom-out-button')), findsOneWidget);
    });

    testWidgets('AC2: tap zoom-in pushes ease target with zoom + 1',
        (tester) async {
      final renderer = FakeMapRenderer();
      await pumpMap(tester, renderer: renderer);

      // Seed display state via the camera-changed callback.
      await renderer.simulateCameraChanged(15.0, 10.318, 123.883);
      await tester.pump();

      await tester.tap(find.byKey(const Key('map.zoom-in-button')));
      await tester.pump();

      expect(renderer.cameraTargetHistory, isNotEmpty);
      final last = renderer.cameraTargetHistory.last;
      expect(last.zoom, 16.0);
      expect(last.animation, CameraAnimation.ease);
    });

    testWidgets('AC3: tap zoom-out pushes ease target with zoom − 1',
        (tester) async {
      final renderer = FakeMapRenderer();
      await pumpMap(tester, renderer: renderer);

      await renderer.simulateCameraChanged(15.0, 10.318, 123.883);
      await tester.pump();

      await tester.tap(find.byKey(const Key('map.zoom-out-button')));
      await tester.pump();

      expect(renderer.cameraTargetHistory, isNotEmpty);
      final last = renderer.cameraTargetHistory.last;
      expect(last.zoom, 14.0);
      expect(last.animation, CameraAnimation.ease);
    });
  });
}
```

- [ ] **Step 2: Run the new test file and confirm it fails**

```bash
flutter test test/features/map/map_screen_zoom_test.dart
```

Expected: compile error / test failure — `Key('map.zoom-in-button')` not found, `simulateCameraChanged` callback never registered (the screen doesn't pass `onCameraChanged` yet), no `ZoomButton` widget exists in the screen.

- [ ] **Step 3: Update `map_screen.dart` imports**

Open `lib/features/map/presentation/map_screen.dart`. Add these imports near the existing `recenter_button` imports:

```dart
import 'package:firecheck/features/map/presentation/zoom_button.dart';
import 'package:firecheck/features/map/presentation/zoom_button_state.dart';
import 'package:firecheck/features/map/presentation/zoom_direction.dart';
```

- [ ] **Step 4: Add the new state fields and rename `_recenterRequestSeq`**

In `_MapScreenState` (right after the existing `_rationaleVisible` field), add:

```dart
double? _displayZoom;
double? _displayLat;
double? _displayLng;
```

Then rename the existing field `_recenterRequestSeq` to `_cameraRequestSeq` everywhere in this file. (As of writing, it appears at the field declaration and in `_onRecenterTap` — at least 5 references.)

Verify after editing:

```bash
grep -n "_recenterRequestSeq\|_cameraRequestSeq" lib/features/map/presentation/map_screen.dart
```

Expected: only `_cameraRequestSeq` matches (no remaining `_recenterRequestSeq`).

- [ ] **Step 5: Add the `_onCameraChanged` handler**

Add this method to `_MapScreenState` (place it near `_onRecenterTap`):

```dart
void _onCameraChanged(double zoom, double lat, double lng) {
  final prevRounded = _displayZoom?.round();
  _displayZoom = zoom;
  _displayLat = lat;
  _displayLng = lng;
  if (prevRounded != zoom.round()) {
    setState(() {});
  }
}
```

- [ ] **Step 6: Add `_onZoomIn` and `_onZoomOut` handlers**

Add to `_MapScreenState`:

```dart
Future<void> _onZoomIn() => _onZoom(1);
Future<void> _onZoomOut() => _onZoom(-1);

Future<void> _onZoom(int delta) async {
  final base = _displayZoom?.round();
  final lat = _displayLat;
  final lng = _displayLng;
  if (base == null || lat == null || lng == null) return;

  final newZoom = (base + delta).clamp(0, 22);
  if (newZoom == base) return;

  setState(() {
    _cameraTarget = CameraTarget(
      lat: lat,
      lng: lng,
      zoom: newZoom.toDouble(),
      requestId: ++_cameraRequestSeq,
      animation: CameraAnimation.ease,
    );
  });
}
```

(Tasks 8 + 9 add `_commandedZoom` anchoring and analytics on top of this. Keeping it minimal here to satisfy the AC2/AC3 tests cleanly.)

- [ ] **Step 7: Pass `onCameraChanged` to the renderer**

Find the `renderer.build(...)` call inside `Scaffold.body`'s `Stack`. Add `onCameraChanged: _onCameraChanged,` to the named arguments:

```dart
: renderer.build(
    context,
    features: features,
    boundaryGeojson: assignment.boundaryPolygonGeojson,
    onFeatureTap: _handleFeatureTap,
    onLongPress: _handleLongPress,
    onCameraChanged: _onCameraChanged,
    addModeActive: _addModeActive,
    initialCameraTarget: initialCameraTarget,
    cameraTarget: _cameraTarget,
  ),
```

- [ ] **Step 8: Mount the two `ZoomButton`s above the recenter button**

Inside the `Stack` children list (in `build`), find the existing `RecenterButton` `Positioned` block. Immediately AFTER it (before the bottom-row `Positioned` with the new-feature pill), add:

```dart
Positioned(
  right: 16,
  bottom: 144,
  child: ZoomButton(
    key: const Key('map.zoom-out-button'),
    direction: ZoomDirection.zoomOut,
    state: ZoomButtonState.idle,
    onTap: _onZoomOut,
  ),
),
Positioned(
  right: 16,
  bottom: 204,
  child: ZoomButton(
    key: const Key('map.zoom-in-button'),
    direction: ZoomDirection.zoomIn,
    state: ZoomButtonState.idle,
    onTap: _onZoomIn,
  ),
),
```

(Disabled-state wiring lands in Task 7. For now both stay `idle` so AC1/AC2/AC3 can drive the orchestration.)

- [ ] **Step 9: Run the new tests and confirm they pass**

```bash
flutter test test/features/map/map_screen_zoom_test.dart
```

Expected: all 3 tests pass (AC1, AC2, AC3).

- [ ] **Step 10: Run the full map test suite to confirm no regression**

```bash
flutter analyze
flutter test test/features/map/
```

Expected: analyzer clean, all map tests still pass — including `map_screen_recenter_test.dart` (its `CameraTarget` defaults to `animation: fly`, recenter behavior unchanged).

- [ ] **Step 11: Commit**

```bash
git add lib/features/map/presentation/map_screen.dart test/features/map/map_screen_zoom_test.dart
git commit -m "feat(map): mount ZoomButtons + _onZoomIn/_onZoomOut handlers (AC1-AC3)"
```

---

## Task 7: Disabled-state derivation (AC4, AC5, AC6)

**Files:**
- Modify: `lib/features/map/presentation/map_screen.dart`
- Modify: `test/features/map/map_screen_zoom_test.dart`

Adds `_zoomInState()` / `_zoomOutState()` so the buttons disable at zoom 22 / 0, and pinch (simulated via `simulateCameraChanged`) flips state in real time.

- [ ] **Step 1: Add the failing tests**

Append to the existing `group('US-13 zoom buttons — mount + tap handlers', () { ... });` in `test/features/map/map_screen_zoom_test.dart`, OR add a sibling group at the bottom of `main()`:

```dart
group('US-13 zoom buttons — disabled state', () {
  // Same pattern recenter_button_test.dart uses: trace from a uniquely-
  // identifying icon up to its single Opacity ancestor.
  Opacity opacityForIcon(WidgetTester tester, IconData icon) {
    return tester.widget<Opacity>(
      find.ancestor(of: find.byIcon(icon), matching: find.byType(Opacity)),
    );
  }

  testWidgets('AC4: at zoom 22, zoom-in button is disabled and ignores taps',
      (tester) async {
    final renderer = FakeMapRenderer();
    await pumpMap(tester, renderer: renderer);

    await renderer.simulateCameraChanged(22.0, 10.318, 123.883);
    await tester.pump();

    final priorHistoryLen = renderer.cameraTargetHistory.length;

    await tester.tap(
      find.byKey(const Key('map.zoom-in-button')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(renderer.cameraTargetHistory.length, priorHistoryLen);
    expect(opacityForIcon(tester, Icons.add).opacity, 0.5);
  });

  testWidgets('AC5: at zoom 0, zoom-out button is disabled and ignores taps',
      (tester) async {
    final renderer = FakeMapRenderer();
    await pumpMap(tester, renderer: renderer);

    await renderer.simulateCameraChanged(0.0, 10.318, 123.883);
    await tester.pump();

    final priorHistoryLen = renderer.cameraTargetHistory.length;

    await tester.tap(
      find.byKey(const Key('map.zoom-out-button')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(renderer.cameraTargetHistory.length, priorHistoryLen);
    expect(opacityForIcon(tester, Icons.remove).opacity, 0.5);
  });

  testWidgets('AC6: pinching to max flips zoom-in to disabled', (tester) async {
    final renderer = FakeMapRenderer();
    await pumpMap(tester, renderer: renderer);

    // Start at a normal zoom — zoom-in button is idle (full opacity).
    await renderer.simulateCameraChanged(15.0, 10.318, 123.883);
    await tester.pump();
    expect(opacityForIcon(tester, Icons.add).opacity, 1.0);

    // User pinches outward; renderer reports max zoom.
    await renderer.simulateCameraChanged(22.0, 10.318, 123.883);
    await tester.pump();

    expect(opacityForIcon(tester, Icons.add).opacity, 0.5);
  });
});
```

(No new imports needed.)

- [ ] **Step 2: Run the new tests and confirm they fail**

```bash
flutter test test/features/map/map_screen_zoom_test.dart
```

Expected: AC4/AC5/AC6 fail because both buttons are still hard-coded to `state: ZoomButtonState.idle`.

- [ ] **Step 3: Add the state-derivation methods**

In `_MapScreenState` (next to `_onZoomIn` / `_onZoomOut`), add:

```dart
ZoomButtonState _zoomInState() {
  final z = _displayZoom?.round();
  if (z == null) return ZoomButtonState.idle;
  return z >= 22 ? ZoomButtonState.disabled : ZoomButtonState.idle;
}

ZoomButtonState _zoomOutState() {
  final z = _displayZoom?.round();
  if (z == null) return ZoomButtonState.idle;
  return z <= 0 ? ZoomButtonState.disabled : ZoomButtonState.idle;
}
```

- [ ] **Step 4: Wire derivation into the mounted buttons**

Replace the two `ZoomButton` mounts inside the `Stack` children with:

```dart
Positioned(
  right: 16,
  bottom: 144,
  child: ZoomButton(
    key: const Key('map.zoom-out-button'),
    direction: ZoomDirection.zoomOut,
    state: _zoomOutState(),
    onTap: _onZoomOut,
  ),
),
Positioned(
  right: 16,
  bottom: 204,
  child: ZoomButton(
    key: const Key('map.zoom-in-button'),
    direction: ZoomDirection.zoomIn,
    state: _zoomInState(),
    onTap: _onZoomIn,
  ),
),
```

- [ ] **Step 5: Run the tests again**

```bash
flutter test test/features/map/map_screen_zoom_test.dart
```

Expected: all 6 tests pass (AC1–AC6).

- [ ] **Step 6: Commit**

```bash
git add lib/features/map/presentation/map_screen.dart test/features/map/map_screen_zoom_test.dart
git commit -m "feat(map): zoom-in/out disabled state at bounds (AC4-AC6)"
```

---

## Task 8: Rapid-tap accumulation + settle timer

**Files:**
- Modify: `lib/features/map/presentation/map_screen.dart`
- Modify: `test/features/map/map_screen_zoom_test.dart`

Adds `_commandedZoom` so 3 rapid taps from zoom 14 cleanly reach 17 (instead of accumulating sub-integer drift mid-animation), plus a 350 ms settle timer that drops `_commandedZoom` so subsequent pinches re-anchor the math.

- [ ] **Step 1: Write the failing tests**

Append a new group at the bottom of `test/features/map/map_screen_zoom_test.dart`:

```dart
group('US-13 zoom buttons — rapid taps + settle timer', () {
  testWidgets('three rapid taps from zoom 14 reach zoom 17', (tester) async {
    final renderer = FakeMapRenderer();
    await pumpMap(tester, renderer: renderer);

    await renderer.simulateCameraChanged(14.0, 10.318, 123.883);
    await tester.pump();

    // Tap three times in a row, before the 350 ms settle timer fires.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('map.zoom-in-button')));
      // Pump a few millis so setState applies and the next tap reads the
      // latest commanded value, but stay well under 350 ms total.
      await tester.pump(const Duration(milliseconds: 50));
    }

    final last = renderer.cameraTargetHistory.last;
    expect(last.zoom, 17.0);
  });

  testWidgets('settle timer drops _commandedZoom; later pinch re-anchors',
      (tester) async {
    final renderer = FakeMapRenderer();
    await pumpMap(tester, renderer: renderer);

    // Start at 15, tap zoom-in once → target 16.
    await renderer.simulateCameraChanged(15.0, 10.318, 123.883);
    await tester.pump();
    await tester.tap(find.byKey(const Key('map.zoom-in-button')));
    await tester.pump();
    expect(renderer.cameraTargetHistory.last.zoom, 16.0);

    // Wait for the settle timer to fire (>350 ms).
    await tester.pump(const Duration(milliseconds: 400));

    // Simulate a pinch landing at zoom 20.
    await renderer.simulateCameraChanged(20.0, 10.318, 123.883);
    await tester.pump();

    // Next zoom-in tap should anchor on the pinched display zoom (20),
    // not the stale commanded zoom (16). Expected target: 21.
    await tester.tap(find.byKey(const Key('map.zoom-in-button')));
    await tester.pump();

    expect(renderer.cameraTargetHistory.last.zoom, 21.0);
  });
});
```

- [ ] **Step 2: Run the tests and confirm they fail**

```bash
flutter test test/features/map/map_screen_zoom_test.dart
```

Expected: the rapid-tap test fails because the current `_onZoom` re-reads `_displayZoom` on every tap (which is mid-animation in widget tests, but more importantly will produce inconsistent results once camera-change events fire mid-animation in real use). The settle test will likely pass coincidentally, but treat it as red until both behaviors are explicit.

- [ ] **Step 3: Add the new state fields**

In `_MapScreenState`, add (next to `_displayZoom`):

```dart
double? _commandedZoom;
Timer? _animationSettleTimer;
```

Make sure `dart:async` is imported at the top of the file (it already is for the existing `_onRecenterTap` orchestration).

- [ ] **Step 4: Update `_onZoom` to anchor on `_commandedZoom`**

Replace the `_onZoom` method body with:

```dart
Future<void> _onZoom(int delta) async {
  // Anchor on commanded if a previous tap is still animating; otherwise
  // anchor on the live display zoom. Bail out cleanly if neither is set
  // (renderer hasn't fired its first onCameraChanged yet — sub-frame race).
  final base = _commandedZoom?.round() ?? _displayZoom?.round();
  final lat = _displayLat;
  final lng = _displayLng;
  if (base == null || lat == null || lng == null) return;

  final newZoom = (base + delta).clamp(0, 22);
  if (newZoom == base) return;

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

- [ ] **Step 5: Update `_zoomInState` / `_zoomOutState` to consider `_commandedZoom`**

Replace both methods with:

```dart
ZoomButtonState _zoomInState() {
  final z = _commandedZoom?.round() ?? _displayZoom?.round();
  if (z == null) return ZoomButtonState.idle;
  return z >= 22 ? ZoomButtonState.disabled : ZoomButtonState.idle;
}

ZoomButtonState _zoomOutState() {
  final z = _commandedZoom?.round() ?? _displayZoom?.round();
  if (z == null) return ZoomButtonState.idle;
  return z <= 0 ? ZoomButtonState.disabled : ZoomButtonState.idle;
}
```

- [ ] **Step 6: Cancel the timer in `dispose`**

Find the `_MapScreenState` class. If it has no `dispose` override, add one:

```dart
@override
void dispose() {
  _animationSettleTimer?.cancel();
  super.dispose();
}
```

If it already has one (it does NOT today — verify with a grep before writing), insert `_animationSettleTimer?.cancel();` before `super.dispose();`.

```bash
grep -n "void dispose" lib/features/map/presentation/map_screen.dart
```

If no match → add the override above.
If a match exists → integrate the cancel call into it.

- [ ] **Step 7: Run the new tests and confirm they pass**

```bash
flutter test test/features/map/map_screen_zoom_test.dart
```

Expected: all 8 tests pass.

- [ ] **Step 8: Run the full map test suite**

```bash
flutter analyze
flutter test test/features/map/
```

Expected: analyzer clean, no regressions.

- [ ] **Step 9: Commit**

```bash
git add lib/features/map/presentation/map_screen.dart test/features/map/map_screen_zoom_test.dart
git commit -m "feat(map): rapid-tap zoom accumulation + 350ms settle timer"
```

---

## Task 9: Analytics

**Files:**
- Modify: `lib/features/map/presentation/map_screen.dart`
- Modify: `test/features/map/map_screen_zoom_test.dart`

Fires `map.zoom.tapped` on each successful (non-bailing) zoom tap. Mirrors the recenter event's shape via `analyticsServiceProvider`.

- [ ] **Step 1: Write the failing test**

Append a new group at the bottom of `test/features/map/map_screen_zoom_test.dart`:

```dart
group('US-13 zoom buttons — analytics', () {
  testWidgets('zoom-in fires map.zoom.tapped with direction=in, from_zoom',
      (tester) async {
    final renderer = FakeMapRenderer();
    final analytics = RecordingAnalyticsService();
    await pumpMap(tester, renderer: renderer, analytics: analytics);

    await renderer.simulateCameraChanged(15.0, 10.318, 123.883);
    await tester.pump();

    await tester.tap(find.byKey(const Key('map.zoom-in-button')));
    await tester.pump();

    expect(analytics.events, hasLength(1));
    expect(analytics.events.single.event, 'map.zoom.tapped');
    expect(
      analytics.events.single.properties,
      {'direction': 'in', 'from_zoom': 15},
    );
  });

  testWidgets('zoom-out fires map.zoom.tapped with direction=out, from_zoom',
      (tester) async {
    final renderer = FakeMapRenderer();
    final analytics = RecordingAnalyticsService();
    await pumpMap(tester, renderer: renderer, analytics: analytics);

    await renderer.simulateCameraChanged(15.0, 10.318, 123.883);
    await tester.pump();

    await tester.tap(find.byKey(const Key('map.zoom-out-button')));
    await tester.pump();

    expect(analytics.events, hasLength(1));
    expect(analytics.events.single.event, 'map.zoom.tapped');
    expect(
      analytics.events.single.properties,
      {'direction': 'out', 'from_zoom': 15},
    );
  });

  testWidgets('disabled tap does NOT fire analytics', (tester) async {
    final renderer = FakeMapRenderer();
    final analytics = RecordingAnalyticsService();
    await pumpMap(tester, renderer: renderer, analytics: analytics);

    await renderer.simulateCameraChanged(22.0, 10.318, 123.883);
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('map.zoom-in-button')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(analytics.events, isEmpty);
  });
});
```

- [ ] **Step 2: Run the new tests and confirm they fail**

```bash
flutter test test/features/map/map_screen_zoom_test.dart
```

Expected: the two "fires …" tests fail (no events recorded). The "disabled tap" test may pass coincidentally.

- [ ] **Step 3: Add the analytics call to `_onZoom`**

Replace `_onZoom` with:

```dart
Future<void> _onZoom(int delta) async {
  final base = _commandedZoom?.round() ?? _displayZoom?.round();
  final lat = _displayLat;
  final lng = _displayLng;
  if (base == null || lat == null || lng == null) return;

  final newZoom = (base + delta).clamp(0, 22);
  if (newZoom == base) return;

  ref.read(analyticsServiceProvider).track(
    'map.zoom.tapped',
    properties: {
      'direction': delta > 0 ? 'in' : 'out',
      'from_zoom': base,
    },
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

(`analyticsServiceProvider` is already imported at the top of `map_screen.dart` for `_onRecenterTap`.)

- [ ] **Step 4: Run the tests again**

```bash
flutter test test/features/map/map_screen_zoom_test.dart
```

Expected: all 11 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/map/presentation/map_screen.dart test/features/map/map_screen_zoom_test.dart
git commit -m "feat(map): emit map.zoom.tapped analytics event on zoom button tap"
```

---

## Task 10: Final regression + manual QA

**Files:** none (verification only).

- [ ] **Step 1: Analyzer clean across the repo**

```bash
flutter analyze
```

Expected: no errors. Resolve any new info-level lints introduced by US-13 in line with the project convention from US-12 (suppress with `// ignore:` only for established cases such as `one_member_abstracts`).

- [ ] **Step 2: Run the full test suite**

```bash
flutter test
```

Expected: all tests pass. Confirm the new `zoom_button_test.dart` (5 cases) and `map_screen_zoom_test.dart` (11 cases) are present in the count, and `map_screen_recenter_test.dart` still passes.

- [ ] **Step 3: Manual QA on a real device or emulator**

Run the app against real Mapbox tiles:

```bash
flutter run
```

Walk through the spec's manual happy path:

1. Open the map → assignment frames correctly (initial camera).
2. Pinch outward to roughly zoom 19 (visually a much closer-in view).
3. Tap **−** three times: the map eases out by ~1 zoom level per tap; transitions feel snappy (~250 ms each).
4. Continue tapping **−** until the button visually dims (opacity 0.5) and stops responding — confirms AC5 against the real Mapbox bound.
5. Tap **+** until it dims at the top end — confirms AC4.
6. Pinch back to a normal zoom; both buttons re-enable.
7. Tap the recenter button — the camera **flies** (slower, 750 ms arc) to the GPS pin at zoom 17. Confirms recenter's `flyTo` path was not broken by the animation switch.
8. Tap zoom buttons again — they now anchor on zoom 17 and step from there.

Verify in the debug console: each zoom tap prints one `[analytics] map.zoom.tapped {...}` line; recenter prints `map.recenter.tapped` as before.

- [ ] **Step 4: Final commit (if any housekeeping fixes were made during regression)**

If steps 1–3 surfaced no changes, skip. Otherwise:

```bash
git add -A
git commit -m "chore(map): post-regression cleanup for US-13"
```

- [ ] **Step 5: Push the branch**

```bash
git push
```

The branch is already named `13-as-an-enumerator-i-want-explicit-zoom-in-and-zoom-out-buttons-...`. After push, open a PR following the project's standard PR flow.

---

## Acceptance Criteria → Task mapping

| AC | Implemented in |
|---|---|
| AC1: zoom-in / zoom-out buttons visible as persistent overlays | Task 6 (mount + AC1 test) |
| AC2: tap zoom-in increments by 1 | Task 6 (AC2 test) |
| AC3: tap zoom-out decrements by 1 | Task 6 (AC3 test) |
| AC4: disabled at max zoom (22) | Task 7 (AC4 test) |
| AC5: disabled at min zoom (0) | Task 7 (AC5 test) |
| AC6: pinch keeps working without interference (and updates disabled state) | Task 7 (AC6 test) — same `_displayZoom` path drives both pinch reactivity and disabled state |
