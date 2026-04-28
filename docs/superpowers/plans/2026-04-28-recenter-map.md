# Recenter Map Button — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a one-tap recenter button to the map screen that flies the camera to the enumerator's current GPS location, with cached-if-accurate fast path, 8s wait + best-effort fallback, rationale-then-OS-prompt permission flow, deniedForever snackbar, and an analytics stub.

**Architecture:** Pure-UI `RecenterButton` widget driven by a `RecenterButtonState` enum. Orchestration (permission gate → cached vs slow path → analytics → snackbars) lives as a private `_onRecenterTap` method on `_MapScreenState` with monotonic-seq cancellation. The `MapRenderer.build()` signature gains `cameraTarget` and `initialCameraTarget` params; `MapboxMapRenderer` calls `MapboxMap.flyTo` in `didUpdateWidget`, while `FakeMapRenderer` records targets for widget-test assertions. New `AnalyticsService` interface with no-op + console + recording impls.

**Tech Stack:** Flutter 3.22 / Dart 3.4+, `mapbox_maps_flutter ^2.5`, `geolocator ^13.0`, `flutter_riverpod ^2.5`, manual `Provider<>(...)` syntax (no codegen), `flutter_test` + `mocktail`, ARB-based i18n via `flutter_localizations` (arb dir `lib/core/i18n/`).

**Spec:** `docs/superpowers/specs/2026-04-28-recenter-map-design.md`

---

## File structure

### Files to create

| Path | Responsibility |
|---|---|
| `lib/core/analytics/analytics_service.dart` | `AnalyticsService` interface + `NoopAnalyticsService` + `ConsoleAnalyticsService` + `RecordingAnalyticsService` |
| `lib/core/analytics/analytics_providers.dart` | Riverpod `analyticsServiceProvider` (Console in debug, Noop in release) |
| `lib/core/geo/polygon_bounds.dart` | Pure helper: `polygonBoundsFromGeojson(String)` returning `PolygonBounds(center, zoom)` |
| `lib/features/map/presentation/camera_target.dart` | Immutable `CameraTarget` (lat, lng, zoom, requestId) — equality by requestId |
| `lib/features/map/presentation/recenter_button_state.dart` | `enum RecenterButtonState { idle, loading, disabled }` |
| `lib/features/map/presentation/recenter_button.dart` | Pure-UI `StatelessWidget` consuming `RecenterButtonState` + `onTap` |
| `test/core/analytics/analytics_service_test.dart` | Unit tests for the three impls |
| `test/core/geo/polygon_bounds_test.dart` | Centroid + zoom-to-fit unit tests |
| `test/features/map/recenter_button_test.dart` | Pure-widget tests for the button |
| `test/features/map/map_screen_recenter_test.dart` | Widget tests for `_onRecenterTap` orchestration (one per AC branch) |

### Files to modify

| Path | Change |
|---|---|
| `lib/core/location/location_service.dart` | Add `checkPermission()` + `openAppSettings()` to interface + `GeolocatorLocationService` + `FakeLocationService` (with `openAppSettingsCalled` recorder) |
| `lib/features/map/presentation/map_renderer.dart` | `MapRenderer.build()` gains `CameraTarget? cameraTarget` and `CameraTarget? initialCameraTarget` (named, optional). `FakeMapRenderer` adds `lastCameraTarget`, `lastInitialCameraTarget`, `cameraTargetHistory`. `_MapboxMapView` stores `MapboxMap?`, accepts initial target, flies in `didUpdateWidget` |
| `lib/features/map/presentation/map_screen.dart` | Delete `_followMe` field + Follow-me pill + on-mount `Future.microtask(requestPermission)`. Mount `RecenterButton` bottom-right. Add `_onRecenterTap`, `_recenterRequestSeq`, `_cameraTarget`, `_recenterState`, `_rationaleVisible`. Compute `initialCameraTarget` from assignment boundary. Pass both targets into renderer |
| `lib/core/i18n/app_en.arb` | Add 8 new keys (see Task 5) |
| `lib/core/i18n/app_tl.arb` | Mirror the 8 keys (English fallback with `// TODO(i18n): translate`) |
| `test/features/map/map_screen_test.dart` | Update the "renders title + follow-me toggle" test to no longer assert on `'Follow'` text (the pill is being removed). |

---

## Task ordering rationale

1. **Foundations first (1-5)**: Pure helpers and value types with no dependencies — `AnalyticsService`, `PolygonBounds`, `CameraTarget`, i18n keys.
2. **Leaf widgets (6)**: `RecenterButton` is pure UI; can be tested without any of the orchestration.
3. **Service-layer changes (7)**: `LocationService` interface gains two methods. Trivial mechanical change; needed before orchestration.
4. **Renderer plumbing (8)**: `MapRenderer` interface change + Fake recorders + Mapbox flyTo. New params are optional with default `null` so existing callers keep compiling.
5. **Refactor (9)**: Delete dead follow-me pill + on-mount permission kick. Update one existing test. Pure refactor; nothing new yet.
6. **Initial framing (10)**: Compute `initialCameraTarget` from boundary; pass to renderer.
7. **Orchestration, branch by branch (11-16)**: Each branch (cache hit, slow success, slow timeout, deniedForever, rationale-allow, rationale-not-now) is one task. TDD red→green per branch.
8. **Final regression (17)**: `flutter analyze`, full test suite, manual QA checklist.

---

## Task 1: `AnalyticsService` — interface, impls, and unit tests

**Files:**
- Create: `lib/core/analytics/analytics_service.dart`
- Create: `test/core/analytics/analytics_service_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/analytics/analytics_service_test.dart`:

```dart
import 'package:firecheck/core/analytics/analytics_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoopAnalyticsService', () {
    test('track is a no-op (no throw)', () {
      const service = NoopAnalyticsService();
      expect(() => service.track('any.event'), returnsNormally);
      expect(
        () => service.track('any.event', properties: {'k': 'v'}),
        returnsNormally,
      );
    });
  });

  group('ConsoleAnalyticsService', () {
    late List<String> printed;
    late DebugPrintCallback original;

    setUp(() {
      printed = <String>[];
      original = debugPrint;
      debugPrint = (String? msg, {int? wrapWidth}) => printed.add(msg ?? '');
    });

    tearDown(() => debugPrint = original);

    test('writes event name only when properties is null', () {
      const ConsoleAnalyticsService().track('map.recenter.tapped');
      expect(printed, ['[analytics] map.recenter.tapped']);
    });

    test('writes JSON-encoded properties when present', () {
      const ConsoleAnalyticsService()
          .track('map.recenter.tapped', properties: {'outcome': 'ok'});
      expect(printed, ['[analytics] map.recenter.tapped {"outcome":"ok"}']);
    });

    test('omits properties suffix when properties map is empty', () {
      const ConsoleAnalyticsService().track('e', properties: <String, Object?>{});
      expect(printed, ['[analytics] e']);
    });
  });

  group('RecordingAnalyticsService', () {
    test('records events in order with their properties', () {
      final svc = RecordingAnalyticsService()
        ..track('a', properties: {'k': 1})
        ..track('b')
        ..track('c', properties: {'k': 2});

      expect(svc.events, hasLength(3));
      expect(svc.events[0].event, 'a');
      expect(svc.events[0].properties, {'k': 1});
      expect(svc.events[1].event, 'b');
      expect(svc.events[1].properties, isNull);
      expect(svc.events[2].event, 'c');
      expect(svc.events[2].properties, {'k': 2});
    });
  });
}
```

- [ ] **Step 2: Run, expect FAIL**

```bash
flutter test test/core/analytics/analytics_service_test.dart
```

Expected: FAIL — "Target of URI doesn't exist: 'package:firecheck/core/analytics/analytics_service.dart'".

- [ ] **Step 3: Write the implementation**

Create `lib/core/analytics/analytics_service.dart`:

```dart
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Surfaces user-action events for usage tracking. Default production
/// impl is [NoopAnalyticsService]; debug builds use [ConsoleAnalyticsService]
/// for visibility while developing. Test code can override the provider with
/// [RecordingAnalyticsService] to assert on emitted events.
abstract class AnalyticsService {
  void track(String event, {Map<String, Object?>? properties});
}

class NoopAnalyticsService implements AnalyticsService {
  const NoopAnalyticsService();

  @override
  void track(String event, {Map<String, Object?>? properties}) {}
}

class ConsoleAnalyticsService implements AnalyticsService {
  const ConsoleAnalyticsService();

  @override
  void track(String event, {Map<String, Object?>? properties}) {
    final hasProps = properties != null && properties.isNotEmpty;
    final suffix = hasProps ? ' ${jsonEncode(properties)}' : '';
    debugPrint('[analytics] $event$suffix');
  }
}

class RecordingAnalyticsService implements AnalyticsService {
  final List<({String event, Map<String, Object?>? properties})> events = [];

  @override
  void track(String event, {Map<String, Object?>? properties}) {
    events.add((event: event, properties: properties));
  }
}
```

- [ ] **Step 4: Run, expect PASS**

```bash
flutter test test/core/analytics/analytics_service_test.dart
```

Expected: PASS — 5 tests passing.

- [ ] **Step 5: Commit**

```bash
git add lib/core/analytics/analytics_service.dart test/core/analytics/analytics_service_test.dart
git commit -m "feat(analytics): add AnalyticsService interface + Noop/Console/Recording impls"
```

---

## Task 2: `analyticsServiceProvider`

**Files:**
- Create: `lib/core/analytics/analytics_providers.dart`

No new tests — the provider's only logic is choosing impl by `kDebugMode`, which is tedious to test (and exercised by every screen that uses analytics).

- [ ] **Step 1: Create the provider file**

Create `lib/core/analytics/analytics_providers.dart`:

```dart
import 'package:firecheck/core/analytics/analytics_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return kDebugMode
      ? const ConsoleAnalyticsService()
      : const NoopAnalyticsService();
});
```

- [ ] **Step 2: Run analyze to verify no errors**

```bash
flutter analyze lib/core/analytics/
```

Expected: "No issues found!"

- [ ] **Step 3: Commit**

```bash
git add lib/core/analytics/analytics_providers.dart
git commit -m "feat(analytics): add analyticsServiceProvider (Console in debug, Noop in release)"
```

---

## Task 3: `PolygonBounds` helper + unit tests

**Files:**
- Create: `lib/core/geo/polygon_bounds.dart`
- Create: `test/core/geo/polygon_bounds_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/core/geo/polygon_bounds_test.dart`:

```dart
import 'package:firecheck/core/geo/polygon_bounds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('polygonBoundsFromGeojson', () {
    test('returns null for empty string', () {
      expect(polygonBoundsFromGeojson(''), isNull);
    });

    test('returns null for malformed JSON', () {
      expect(polygonBoundsFromGeojson('not json'), isNull);
    });

    test('returns null for non-Polygon types', () {
      expect(
        polygonBoundsFromGeojson('{"type":"Point","coordinates":[0,0]}'),
        isNull,
      );
    });

    test('computes centroid of a small square polygon', () {
      // 0.001° square (~111m on a side) around (10.31810, 123.88270)
      // GeoJSON coords are [lng, lat]
      const geojson = '''
{"type":"Polygon","coordinates":[[
  [123.882, 10.317],
  [123.884, 10.317],
  [123.884, 10.319],
  [123.882, 10.319],
  [123.882, 10.317]
]]}''';
      final bounds = polygonBoundsFromGeojson(geojson);
      expect(bounds, isNotNull);
      expect(bounds!.center.lat, closeTo(10.318, 1e-6));
      expect(bounds.center.lng, closeTo(123.883, 1e-6));
    });

    test('zoom is clamped to 18 for tiny polygons', () {
      // ~10m square — well below the zoom-18 ground resolution
      const geojson = '''
{"type":"Polygon","coordinates":[[
  [123.88270, 10.31810],
  [123.88280, 10.31810],
  [123.88280, 10.31820],
  [123.88270, 10.31820],
  [123.88270, 10.31810]
]]}''';
      final bounds = polygonBoundsFromGeojson(geojson)!;
      expect(bounds.zoom, 18.0);
    });

    test('zoom is clamped to 12 for huge polygons', () {
      // ~10° span — covers half a country
      const geojson = '''
{"type":"Polygon","coordinates":[[
  [120.0, 5.0],
  [130.0, 5.0],
  [130.0, 15.0],
  [120.0, 15.0],
  [120.0, 5.0]
]]}''';
      final bounds = polygonBoundsFromGeojson(geojson)!;
      expect(bounds.zoom, 12.0);
    });

    test('zoom is monotonic with bounding-box size', () {
      String squareJson(double size) {
        const lat = 10.318;
        const lng = 123.883;
        final h = size / 2;
        return '{"type":"Polygon","coordinates":[[ '
            '[${lng - h},${lat - h}], '
            '[${lng + h},${lat - h}], '
            '[${lng + h},${lat + h}], '
            '[${lng - h},${lat + h}], '
            '[${lng - h},${lat - h}]]]}';
      }

      final small = polygonBoundsFromGeojson(squareJson(0.001))!;
      final medium = polygonBoundsFromGeojson(squareJson(0.01))!;
      final large = polygonBoundsFromGeojson(squareJson(0.1))!;

      expect(small.zoom >= medium.zoom, isTrue);
      expect(medium.zoom >= large.zoom, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run, expect FAIL**

```bash
flutter test test/core/geo/polygon_bounds_test.dart
```

Expected: FAIL — "Target of URI doesn't exist".

- [ ] **Step 3: Write the implementation**

Create `lib/core/geo/polygon_bounds.dart`:

```dart
import 'dart:convert';
import 'dart:math' as math;

class LatLng {
  const LatLng(this.lat, this.lng);
  final double lat;
  final double lng;
}

class PolygonBounds {
  const PolygonBounds({required this.center, required this.zoom});
  final LatLng center;
  final double zoom;
}

/// Computes a bounding-box centroid and a zoom-to-fit zoom level for a
/// GeoJSON Polygon. Returns null if the input is empty, malformed, or not
/// a Polygon. Zoom is clamped to [12, 18] — too far out fails to show
/// useful context, too far in over-magnifies tiny boundaries.
PolygonBounds? polygonBoundsFromGeojson(String geojson) {
  if (geojson.isEmpty) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(geojson);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  if (decoded['type'] != 'Polygon') return null;
  final coords = decoded['coordinates'];
  if (coords is! List<Object?>) return null;
  if (coords.isEmpty) return null;

  double minLat = double.infinity, maxLat = -double.infinity;
  double minLng = double.infinity, maxLng = -double.infinity;
  var pointCount = 0;

  for (final ring in coords) {
    if (ring is! List<Object?>) return null;
    for (final p in ring) {
      if (p is! List<Object?>) return null;
      if (p.length < 2) return null;
      final lng = p[0];
      final lat = p[1];
      if (lng is! num || lat is! num) return null;
      minLat = math.min(minLat, lat.toDouble());
      maxLat = math.max(maxLat, lat.toDouble());
      minLng = math.min(minLng, lng.toDouble());
      maxLng = math.max(maxLng, lng.toDouble());
      pointCount++;
    }
  }
  if (pointCount == 0) return null;

  final centerLat = (minLat + maxLat) / 2.0;
  final centerLng = (minLng + maxLng) / 2.0;

  // Bounding-box diagonal in meters (haversine on the diagonal corners).
  final diagonalM = _haversineMeters(minLat, minLng, maxLat, maxLng);

  // Mapbox/Web Mercator ground resolution at the equator at zoom z is
  // ~156543.03 / 2^z meters per pixel. Latitude scaling: multiply by cos(lat).
  // Pick zoom so the diagonal fits in ~512 pixels (a comfortable viewport).
  const targetPixels = 512.0;
  final cosLat = math.cos(centerLat * math.pi / 180.0).abs();
  // groundRes = diagonalM / targetPixels
  // 156543.03 * cosLat / 2^z = groundRes  ==>  z = log2(156543.03 * cosLat / groundRes)
  final groundRes = diagonalM / targetPixels;
  final rawZoom = math.log(156543.03 * cosLat / groundRes) / math.ln2;
  final zoom = rawZoom.clamp(12.0, 18.0);

  return PolygonBounds(center: LatLng(centerLat, centerLng), zoom: zoom);
}

double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusM = 6371000.0;
  final dLat = (lat2 - lat1) * math.pi / 180.0;
  final dLng = (lng2 - lng1) * math.pi / 180.0;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180.0) *
          math.cos(lat2 * math.pi / 180.0) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusM * c;
}
```

- [ ] **Step 4: Run, expect PASS**

```bash
flutter test test/core/geo/polygon_bounds_test.dart
```

Expected: PASS — 6 tests passing.

- [ ] **Step 5: Commit**

```bash
git add lib/core/geo/polygon_bounds.dart test/core/geo/polygon_bounds_test.dart
git commit -m "feat(geo): add polygonBoundsFromGeojson helper for initial map framing"
```

---

## Task 4: `CameraTarget` value type

**Files:**
- Create: `lib/features/map/presentation/camera_target.dart`
- Create: `test/features/map/camera_target_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/map/camera_target_test.dart`:

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
}
```

- [ ] **Step 2: Run, expect FAIL**

```bash
flutter test test/features/map/camera_target_test.dart
```

Expected: FAIL — "Target of URI doesn't exist".

- [ ] **Step 3: Write the implementation**

Create `lib/features/map/presentation/camera_target.dart`:

```dart
import 'package:flutter/foundation.dart';

/// A camera-fly request from the screen to the renderer.
///
/// Equality is on [requestId] only so two taps producing identical
/// coordinates still trigger a fresh fly: the renderer's didUpdateWidget
/// detects "different requestId" → flyTo. This is intentional — without it,
/// repeat taps at the same position would be no-ops.
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

- [ ] **Step 4: Run, expect PASS**

```bash
flutter test test/features/map/camera_target_test.dart
```

Expected: PASS — 1 test passing.

- [ ] **Step 5: Commit**

```bash
git add lib/features/map/presentation/camera_target.dart test/features/map/camera_target_test.dart
git commit -m "feat(map): add CameraTarget value type (equality by requestId)"
```

---

## Task 5: i18n keys

**Files:**
- Modify: `lib/core/i18n/app_en.arb`
- Modify: `lib/core/i18n/app_tl.arb`

The Tagalog file gets the same English text initially with an inline TODO — this story does not commit to a translation; a follow-up i18n pass owns it.

- [ ] **Step 1: Add the 8 keys to `app_en.arb`**

Append (preserving the trailing `}`) to `lib/core/i18n/app_en.arb`:

```json
"recenterButtonSemanticLabel": "Recenter map on my location",
"locationRationaleTitle": "Use your location",
"locationRationaleBody": "FireCheck uses your GPS to center the map on you so you can quickly orient yourself in the field. We only access location while you have the app open.",
"locationRationaleAllow": "Allow",
"locationRationaleNotNow": "Not now",
"locationSnackbarPermanentlyDenied": "Location permission denied. Open settings to enable it.",
"locationSnackbarOpenSettings": "Open settings",
"locationSnackbarLowAccuracy": "Location accuracy is low. Showing your approximate position."
```

- [ ] **Step 2: Mirror the keys in `app_tl.arb`**

Append the same 8 keys with English values + TODO comment so the build doesn't fail on missing translations:

```json
"//": "TODO(i18n): translate the 8 recenter-map keys below to Tagalog",
"recenterButtonSemanticLabel": "Recenter map on my location",
"locationRationaleTitle": "Use your location",
"locationRationaleBody": "FireCheck uses your GPS to center the map on you so you can quickly orient yourself in the field. We only access location while you have the app open.",
"locationRationaleAllow": "Allow",
"locationRationaleNotNow": "Not now",
"locationSnackbarPermanentlyDenied": "Location permission denied. Open settings to enable it.",
"locationSnackbarOpenSettings": "Open settings",
"locationSnackbarLowAccuracy": "Location accuracy is low. Showing your approximate position."
```

(Note: ARB files don't support comments natively — the `"//"` key is a documented convention for arb file comments. If `flutter gen-l10n` complains, swap to a `@@x-comments` block per the ARB spec.)

- [ ] **Step 3: Regenerate localizations**

```bash
flutter gen-l10n
```

Expected: regenerates `lib/generated/l10n/app_localizations.dart` with the 8 new accessors. No errors.

- [ ] **Step 4: Verify with analyzer**

```bash
flutter analyze lib/generated/l10n/
```

Expected: "No issues found!"

- [ ] **Step 5: Commit**

```bash
git add lib/core/i18n/app_en.arb lib/core/i18n/app_tl.arb lib/generated/l10n/
git commit -m "i18n: add 8 keys for recenter button + permission dialogs/snackbars"
```

---

## Task 6: `RecenterButtonState` enum + `RecenterButton` widget

**Files:**
- Create: `lib/features/map/presentation/recenter_button_state.dart`
- Create: `lib/features/map/presentation/recenter_button.dart`
- Create: `test/features/map/recenter_button_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/features/map/recenter_button_test.dart`:

```dart
import 'package:firecheck/features/map/presentation/recenter_button.dart';
import 'package:firecheck/features/map/presentation/recenter_button_state.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ));
    await tester.pump();
  }

  group('RecenterButton', () {
    testWidgets('idle: renders my_location icon and tap invokes onTap',
        (tester) async {
      var taps = 0;
      await pump(
        tester,
        RecenterButton(
          state: RecenterButtonState.idle,
          onTap: () => taps++,
        ),
      );
      expect(find.byIcon(Icons.my_location), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.byType(RecenterButton));
      expect(taps, 1);
    });

    testWidgets('loading: renders spinner; taps do NOT invoke onTap',
        (tester) async {
      var taps = 0;
      await pump(
        tester,
        RecenterButton(
          state: RecenterButtonState.loading,
          onTap: () => taps++,
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.my_location), findsNothing);

      await tester.tap(find.byType(RecenterButton), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('disabled: renders icon at reduced opacity; no taps',
        (tester) async {
      var taps = 0;
      await pump(
        tester,
        RecenterButton(
          state: RecenterButtonState.disabled,
          onTap: () => taps++,
        ),
      );
      expect(find.byIcon(Icons.my_location), findsOneWidget);

      // Disabled rendering wraps the button in an Opacity of 0.5.
      final opacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.byIcon(Icons.my_location),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 0.5);

      await tester.tap(find.byType(RecenterButton), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('has the recenterButtonSemanticLabel semantic label',
        (tester) async {
      await pump(
        tester,
        RecenterButton(
          state: RecenterButtonState.idle,
          onTap: () {},
        ),
      );
      expect(
        find.bySemanticsLabel('Recenter map on my location'),
        findsOneWidget,
      );
    });
  });
}
```

- [ ] **Step 2: Run, expect FAIL**

```bash
flutter test test/features/map/recenter_button_test.dart
```

Expected: FAIL — files don't exist.

- [ ] **Step 3: Create the enum**

Create `lib/features/map/presentation/recenter_button_state.dart`:

```dart
enum RecenterButtonState { idle, loading, disabled }
```

- [ ] **Step 4: Create the widget**

Create `lib/features/map/presentation/recenter_button.dart`:

```dart
import 'package:firecheck/features/map/presentation/recenter_button_state.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class RecenterButton extends StatelessWidget {
  const RecenterButton({
    super.key,
    required this.state,
    required this.onTap,
  });

  final RecenterButtonState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final isLoading = state == RecenterButtonState.loading;
    final isDisabled = state == RecenterButtonState.disabled;
    final isInteractive = state == RecenterButtonState.idle;

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
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(colors.onPrimary),
                    ),
                  )
                : Icon(Icons.my_location, color: colors.onPrimary, size: 24),
          ),
        ),
      ),
    );

    return Semantics(
      label: l.recenterButtonSemanticLabel,
      button: true,
      enabled: isInteractive,
      child: Opacity(opacity: isDisabled ? 0.5 : 1.0, child: child),
    );
  }
}
```

- [ ] **Step 5: Run, expect PASS**

```bash
flutter test test/features/map/recenter_button_test.dart
```

Expected: PASS — 4 tests passing.

- [ ] **Step 6: Commit**

```bash
git add lib/features/map/presentation/recenter_button_state.dart \
        lib/features/map/presentation/recenter_button.dart \
        test/features/map/recenter_button_test.dart
git commit -m "feat(map): add RecenterButton widget (idle/loading/disabled states)"
```

---

## Task 7: `LocationService` — `checkPermission()` + `openAppSettings()`

**Files:**
- Modify: `lib/core/location/location_service.dart`

The change is mechanical — split the existing combined `requestPermission` into a pure `checkPermission` (no prompt) plus an unchanged `requestPermission` (still prompts). Add `openAppSettings`. Update both `GeolocatorLocationService` and `FakeLocationService`. The new `FakeLocationService` constructor uses two distinct fields for check/request results so tests can simulate "denied → user grants on prompt" sequences.

No existing test files reference `FakeLocationService` (verified by `grep -rn FakeLocationService --include="*.dart"`), so this is a safe constructor change.

- [ ] **Step 1: Write the failing test**

Create `test/core/location/location_service_test.dart`:

```dart
import 'package:firecheck/core/location/location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  group('FakeLocationService', () {
    test('checkPermission returns the configured result without side effects', () async {
      final svc = FakeLocationService(
        checkPermissionResult: LocationPermission.denied,
      );
      expect(await svc.checkPermission(), LocationPermission.denied);
      // calling check should not flip request — they're independent.
      expect(await svc.requestPermission(), LocationPermission.whileInUse);
    });

    test('requestPermission returns the configured result', () async {
      final svc = FakeLocationService(
        requestPermissionResult: LocationPermission.deniedForever,
      );
      expect(await svc.requestPermission(), LocationPermission.deniedForever);
    });

    test('openAppSettings flips the recorder and returns true', () async {
      final svc = FakeLocationService();
      expect(svc.openAppSettingsCalled, isFalse);
      expect(await svc.openAppSettings(), isTrue);
      expect(svc.openAppSettingsCalled, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run, expect FAIL**

```bash
flutter test test/core/location/location_service_test.dart
```

Expected: FAIL — `checkPermission`, `openAppSettings`, `checkPermissionResult`, `requestPermissionResult`, `openAppSettingsCalled` don't exist.

- [ ] **Step 3: Update `lib/core/location/location_service.dart`**

Replace the entire file contents with:

```dart
import 'package:geolocator/geolocator.dart';

/// Narrow interface so widget tests can substitute a fake.
abstract class LocationService {
  /// Pure check — does NOT prompt the OS for permission. Use before
  /// showing a rationale dialog.
  Future<LocationPermission> checkPermission();

  /// Prompts the OS for permission if currently `denied`. Returns the
  /// post-prompt state.
  Future<LocationPermission> requestPermission();

  Future<bool> isLocationServiceEnabled();
  Stream<Position> positionStream();
  Future<Position?> lastKnownPosition();

  /// Opens the OS app settings page so the user can manually grant a
  /// previously deniedForever permission. Returns true if the page was
  /// successfully opened.
  Future<bool> openAppSettings();
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() async {
    final existing = await Geolocator.checkPermission();
    if (existing == LocationPermission.denied) {
      return Geolocator.requestPermission();
    }
    return existing;
  }

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Stream<Position> positionStream() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        ),
      );

  @override
  Future<Position?> lastKnownPosition() => Geolocator.getLastKnownPosition();

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
}

/// In-memory fake for tests — emits whatever you seed, never touches
/// platform channels.
class FakeLocationService implements LocationService {
  FakeLocationService({
    this.checkPermissionResult = LocationPermission.whileInUse,
    this.requestPermissionResult = LocationPermission.whileInUse,
    this.serviceEnabled = true,
    this.positions = const Stream<Position>.empty(),
    this.lastKnown,
  });

  LocationPermission checkPermissionResult;
  LocationPermission requestPermissionResult;
  bool serviceEnabled;
  Stream<Position> positions;
  Position? lastKnown;

  /// Test recorder: flips to true the first time openAppSettings is called.
  bool openAppSettingsCalled = false;

  @override
  Future<LocationPermission> checkPermission() async => checkPermissionResult;

  @override
  Future<LocationPermission> requestPermission() async => requestPermissionResult;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Stream<Position> positionStream() => positions;

  @override
  Future<Position?> lastKnownPosition() async => lastKnown;

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCalled = true;
    return true;
  }
}
```

- [ ] **Step 4: Run, expect PASS for the new test**

```bash
flutter test test/core/location/location_service_test.dart
```

Expected: PASS — 3 tests passing.

- [ ] **Step 5: Run the full test suite to confirm no regressions**

```bash
flutter test
```

Expected: PASS — all existing tests still green. (Note: `map_screen.dart:39-41` still calls the old single-method `requestPermission()` which still works — its signature hasn't changed.)

- [ ] **Step 6: Commit**

```bash
git add lib/core/location/location_service.dart test/core/location/location_service_test.dart
git commit -m "feat(location): split checkPermission()/requestPermission() + add openAppSettings()"
```

---

## Task 8: `MapRenderer` signature change + `MapboxMapRenderer` flyTo + `FakeMapRenderer` recorders

**Files:**
- Modify: `lib/features/map/presentation/map_renderer.dart`

Both new params (`cameraTarget`, `initialCameraTarget`) are named optional with default `null`, so existing callers continue to compile unchanged.

`MapboxMapRenderer` work:
1. Store `MapboxMap?` ref during `_onMapCreated` so `flyTo` has something to call against.
2. Use `initialCameraTarget` (if non-null) to set the map's initial `cameraOptions`; else fall back to the existing hard-coded `(123.88270, 10.31810)` zoom 15 (kept for now; the boundary-derived initial target will replace it once map_screen passes it in Task 10).
3. In `didUpdateWidget`, when `cameraTarget` changed (by requestId), call `MapboxMap.flyTo(...)` with `MapAnimationOptions(duration: 750)`.

`FakeMapRenderer` work:
- Add `lastCameraTarget`, `lastInitialCameraTarget`, `cameraTargetHistory` fields.
- Populate them in `build`.

This task has no widget test — the Mapbox plugin doesn't render in `flutter_tester`. The fake recorders are exercised in Tasks 10–16. Manual QA covers MapboxMapRenderer.

- [ ] **Step 1: Modify the `MapRenderer` interface**

Replace the abstract class block in `lib/features/map/presentation/map_renderer.dart` (lines ~14–24) with:

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
    bool addModeActive,
    CameraTarget? cameraTarget,
    CameraTarget? initialCameraTarget,
  });
}
```

Add the import at the top of the file:

```dart
import 'package:firecheck/features/map/presentation/camera_target.dart';
```

- [ ] **Step 2: Add recorders to `FakeMapRenderer`**

Update the `FakeMapRenderer` class (around lines ~28–85). Add fields:

```dart
class FakeMapRenderer implements MapRenderer {
  void Function(double, double)? _lastOnLongPress;

  CameraTarget? lastCameraTarget;
  CameraTarget? lastInitialCameraTarget;
  final List<CameraTarget> cameraTargetHistory = [];

  // ... existing simulateLongPress + _colorForStatus unchanged ...
```

Update its `build` signature to accept and record the new params:

```dart
  @override
  Widget build(
    BuildContext context, {
    required List<Feature> features,
    required String boundaryGeojson,
    required void Function(Feature) onFeatureTap,
    void Function(double lat, double lng)? onLongPress,
    bool addModeActive = false,
    CameraTarget? cameraTarget,
    CameraTarget? initialCameraTarget,
  }) {
    _lastOnLongPress = onLongPress;
    lastInitialCameraTarget = initialCameraTarget;
    if (cameraTarget != null && cameraTarget != lastCameraTarget) {
      cameraTargetHistory.add(cameraTarget);
    }
    lastCameraTarget = cameraTarget;
    // ... existing ListView body unchanged ...
  }
```

(Recording on equality-by-requestId is intentional — the fake mirrors the real renderer's "fly only on requestId change" behavior, so tests counting `cameraTargetHistory.length` correspond to actual fly events.)

- [ ] **Step 3: Add `MapboxMap?` storage + `flyTo` to `_MapboxMapView`**

Update `_MapboxMapView` and `_MapboxMapViewState` (around lines ~115–197). Add `cameraTarget` + `initialCameraTarget` to the widget's constructor:

```dart
class _MapboxMapView extends StatefulWidget {
  const _MapboxMapView({
    required this.features,
    required this.boundaryGeojson,
    required this.onFeatureTap,
    this.onLongPress,
    this.addModeActive = false,
    this.cameraTarget,
    this.initialCameraTarget,
  });

  final List<Feature> features;
  final String boundaryGeojson;
  final void Function(Feature) onFeatureTap;
  final void Function(double lat, double lng)? onLongPress;
  final bool addModeActive;
  final CameraTarget? cameraTarget;
  final CameraTarget? initialCameraTarget;

  @override
  State<_MapboxMapView> createState() => _MapboxMapViewState();
}
```

In `_MapboxMapViewState`, add a `MapboxMap?` field:

```dart
class _MapboxMapViewState extends State<_MapboxMapView> {
  PolygonAnnotationManager? _featureManager;
  PolygonAnnotationManager? _boundaryManager;
  PointAnnotationManager? _pointManager;
  MapboxMap? _mapboxMap;

  // ... existing _annotationToFeature unchanged ...
```

Update the `build` method's `cameraOptions` to use `initialCameraTarget` when provided:

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
      styleUri: 'mapbox://styles/mapbox/streets-v12',
      onMapCreated: _onMapCreated,
      onLongTapListener: (MapContentGestureContext ctx) {
        if (widget.addModeActive && widget.onLongPress != null) {
          final pos = ctx.point.coordinates;
          widget.onLongPress!(pos.lat.toDouble(), pos.lng.toDouble());
        }
      },
    );
  }
```

Store the `MapboxMap` in `_onMapCreated` (add at the very top of the existing method):

```dart
  Future<void> _onMapCreated(MapboxMap map) async {
    _mapboxMap = map;
    // ... existing body unchanged ...
  }
```

Add the `flyTo` reaction at the end of `didUpdateWidget`:

```dart
  @override
  void didUpdateWidget(covariant _MapboxMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final featuresChanged = oldWidget.features != widget.features;
    final boundaryChanged = oldWidget.boundaryGeojson != widget.boundaryGeojson;
    if (featuresChanged && _featureManager != null) {
      unawaited(_rerenderFeatures());
    }
    if (boundaryChanged && _boundaryManager != null) {
      unawaited(_rerenderBoundary());
    }
    final target = widget.cameraTarget;
    if (target != null && target != oldWidget.cameraTarget) {
      unawaited(_flyToCameraTarget(target));
    }
  }

  Future<void> _flyToCameraTarget(CameraTarget t) async {
    final map = _mapboxMap;
    if (map == null) return; // _onMapCreated hasn't run yet
    await map.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(t.lng, t.lat)),
        zoom: t.zoom,
      ),
      MapAnimationOptions(duration: 750),
    );
  }
```

Update `MapboxMapRenderer.build` to forward the two new params to `_MapboxMapView`:

```dart
class MapboxMapRenderer implements MapRenderer {
  @override
  Widget build(
    BuildContext context, {
    required List<Feature> features,
    required String boundaryGeojson,
    required void Function(Feature) onFeatureTap,
    void Function(double lat, double lng)? onLongPress,
    bool addModeActive = false,
    CameraTarget? cameraTarget,
    CameraTarget? initialCameraTarget,
  }) {
    return _MapboxMapView(
      features: features,
      boundaryGeojson: boundaryGeojson,
      onFeatureTap: onFeatureTap,
      onLongPress: onLongPress,
      addModeActive: addModeActive,
      cameraTarget: cameraTarget,
      initialCameraTarget: initialCameraTarget,
    );
  }
}
```

- [ ] **Step 4: Run analyze + the full test suite**

```bash
flutter analyze lib/features/map/
flutter test
```

Expected: "No issues found!" + all existing tests still PASS. The new params default to `null`, so existing test code calling `renderer.build(...)` without them continues to work.

- [ ] **Step 5: Commit**

```bash
git add lib/features/map/presentation/map_renderer.dart
git commit -m "feat(map): renderer accepts cameraTarget + initialCameraTarget; flyTo on change"
```

---

## Task 9: Delete dead "Follow me" pill + on-mount permission kick

**Files:**
- Modify: `lib/features/map/presentation/map_screen.dart`
- Modify: `test/features/map/map_screen_test.dart`

Pure refactor. The `_followMe` state field, the Follow-me pill (`map_screen.dart:104-108`), and the on-mount `Future.microtask(requestPermission)` (`map_screen.dart:39-41`) all go away. The existing test at `test/features/map/map_screen_test.dart` line 41 asserts `find.text('Follow')` — update it to assert the pill is absent.

- [ ] **Step 1: Update the existing failing assertion**

In `test/features/map/map_screen_test.dart`, find the test:

```dart
testWidgets('renders title + follow-me toggle', (tester) async {
  await tester.pumpWidget(buildSubject(features: const []));
  await tester.pump();
  expect(find.text('Gather Data'), findsOneWidget);
  expect(find.text('Follow'), findsOneWidget);
});
```

Replace it with:

```dart
testWidgets('renders title; no Follow-me pill (deleted in US-12)',
    (tester) async {
  await tester.pumpWidget(buildSubject(features: const []));
  await tester.pump();
  expect(find.text('Gather Data'), findsOneWidget);
  expect(find.text('Follow'), findsNothing);
});
```

- [ ] **Step 2: Run, expect FAIL**

```bash
flutter test test/features/map/map_screen_test.dart
```

Expected: FAIL — "Follow" is still on screen because the pill is still there.

- [ ] **Step 3: Edit `map_screen.dart` — delete `_followMe`, the pill, the on-mount kick**

In `lib/features/map/presentation/map_screen.dart`:

(a) Delete the field at line ~30:

```dart
// DELETE this line:
bool _followMe = true;
```

(b) Delete the `initState` method body (lines ~33–42); remove the entire override since there's no other initState work. Result: no `initState` override on `_MapScreenState` at all.

(c) Delete the Follow-me pill child + its trailing `SizedBox` (lines ~104–109). The `Row` previously had:

```dart
children: [
  _pill(
    l.followMe,
    on: _followMe,
    onTap: () => setState(() => _followMe = !_followMe),
  ),
  const SizedBox(width: 6),
  Expanded(
    child: Consumer( ... add-feature pill ...),
  ),
],
```

After deletion:

```dart
children: [
  Expanded(
    child: Consumer( ... add-feature pill ...),
  ),
],
```

(With only one child, the `Row` could be replaced by the `Consumer` directly — leave that simplification for Task 10 when the bottom-right button is also being added; minimizing churn here.)

- [ ] **Step 4: Run the full test suite**

```bash
flutter test
```

Expected: PASS — `map_screen_test.dart` and `map_screen_add_mode_test.dart` both green; updated assertion satisfied.

- [ ] **Step 5: Commit**

```bash
git add lib/features/map/presentation/map_screen.dart test/features/map/map_screen_test.dart
git commit -m "refactor(map): delete dead Follow-me pill + on-mount permission kick"
```

---

## Task 10: Compute `initialCameraTarget` from assignment boundary

**Files:**
- Modify: `lib/features/map/presentation/map_screen.dart`
- Modify: `test/features/map/map_screen_test.dart`

After this task, the map opens framed on the assignment boundary instead of the hard-coded Cebu fallback when a boundary is available.

- [ ] **Step 1: Write the failing test**

Append to `test/features/map/map_screen_test.dart`:

```dart
testWidgets('passes a boundary-derived initialCameraTarget to the renderer',
    (tester) async {
  final renderer = FakeMapRenderer();
  final assignment = Assignment(
    id: 'a1',
    enumeratorEmail: 'e@example.com',
    barangayName: 'B',
    cityName: 'C',
    boundaryPolygonGeojson:
        '{"type":"Polygon","coordinates":[[ '
        '[123.882,10.317],[123.884,10.317],'
        '[123.884,10.319],[123.882,10.319],'
        '[123.882,10.317]]]}',
    receivedAt: DateTime.now(),
  );

  await tester.pumpWidget(ProviderScope(
    overrides: [
      mapRendererProvider.overrideWithValue(renderer),
      currentFeaturesProvider.overrideWith((_) => Stream.value(const [])),
      currentAssignmentProvider.overrideWith((_) => Stream.value(assignment)),
      assignmentLockStateProvider.overrideWith((_) => Stream.value(const Unlocked())),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MapScreen(),
    ),
  ));
  await tester.pump();

  expect(renderer.lastInitialCameraTarget, isNotNull);
  expect(renderer.lastInitialCameraTarget!.lat, closeTo(10.318, 1e-3));
  expect(renderer.lastInitialCameraTarget!.lng, closeTo(123.883, 1e-3));
  expect(
    renderer.lastInitialCameraTarget!.zoom,
    inInclusiveRange(12.0, 18.0),
  );
});
```

(The test reuses imports already present in `map_screen_test.dart`: `Assignment` from `database.dart`, `currentAssignmentProvider`, `currentFeaturesProvider`, `assignmentLockStateProvider`, `Unlocked`.)

- [ ] **Step 2: Run, expect FAIL**

```bash
flutter test test/features/map/map_screen_test.dart
```

Expected: FAIL — `lastInitialCameraTarget` is null because `MapScreen` doesn't pass anything yet.

- [ ] **Step 3: Wire the initial target in `map_screen.dart`**

Add the import:

```dart
import 'package:firecheck/core/geo/polygon_bounds.dart';
import 'package:firecheck/features/map/presentation/camera_target.dart';
```

Inside `_MapScreenState.build()`, after `final mapReady = assignment != null && features != null;`, add:

```dart
final bounds = assignment != null
    ? polygonBoundsFromGeojson(assignment.boundaryPolygonGeojson)
    : null;
final initialCameraTarget = bounds != null
    ? CameraTarget(
        lat: bounds.center.lat,
        lng: bounds.center.lng,
        zoom: bounds.zoom,
        requestId: 0,
      )
    : null;
```

Pass it into `renderer.build(...)`:

```dart
renderer.build(
  context,
  features: features,
  boundaryGeojson: assignment.boundaryPolygonGeojson,
  onFeatureTap: _handleFeatureTap,
  onLongPress: _handleLongPress,
  addModeActive: _addModeActive,
  initialCameraTarget: initialCameraTarget,
)
```

- [ ] **Step 4: Run, expect PASS**

```bash
flutter test test/features/map/map_screen_test.dart
```

Expected: PASS — the new test plus all previous tests green.

- [ ] **Step 5: Commit**

```bash
git add lib/features/map/presentation/map_screen.dart test/features/map/map_screen_test.dart
git commit -m "feat(map): frame initial camera on assignment boundary (was hard-coded Cebu)"
```

---

## Task 11: Mount `RecenterButton` + cache fast path

**Files:**
- Modify: `lib/features/map/presentation/map_screen.dart`
- Create: `test/features/map/map_screen_recenter_test.dart`

This task introduces the orchestration scaffold (`_recenterState`, `_recenterRequestSeq`, `_cameraTarget`, `_rationaleVisible`, `_onRecenterTap`) and implements the **happy path** only: permission granted, cached fix accuracy ≤ 100 m → fly + analytics. The slow path, timeout, deniedForever, and rationale paths come in Tasks 12–16, each adding one branch.

- [ ] **Step 1: Write the failing test**

Create `test/features/map/map_screen_recenter_test.dart`:

```dart
import 'dart:async';

import 'package:firecheck/core/analytics/analytics_providers.dart';
import 'package:firecheck/core/analytics/analytics_service.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/location/location_providers.dart';
import 'package:firecheck/core/location/location_service.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/map/presentation/map_providers.dart';
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:firecheck/features/map/presentation/map_screen.dart';
import 'package:firecheck/features/map/presentation/recenter_button.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

Position fakePos({
  required double lat,
  required double lng,
  required double accuracy,
}) {
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: DateTime.utc(2026, 1, 1),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

Assignment fakeAssignment() => Assignment(
      id: 'a1',
      enumeratorEmail: 'e@example.com',
      barangayName: 'B',
      cityName: 'C',
      boundaryPolygonGeojson:
          '{"type":"Polygon","coordinates":[[[123.882,10.317],'
          '[123.884,10.317],[123.884,10.319],'
          '[123.882,10.319],[123.882,10.317]]]}',
      receivedAt: DateTime(2026),
    );

Future<void> pumpMap(
  WidgetTester tester, {
  required FakeMapRenderer renderer,
  required FakeLocationService locationService,
  required AnalyticsService analytics,
  Stream<Position>? positionStream,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mapRendererProvider.overrideWithValue(renderer),
      locationServiceProvider.overrideWithValue(locationService),
      analyticsServiceProvider.overrideWithValue(analytics),
      currentFeaturesProvider.overrideWith((_) => Stream.value(const [])),
      currentAssignmentProvider.overrideWith((_) => Stream.value(fakeAssignment())),
      assignmentLockStateProvider.overrideWith((_) => Stream.value(const Unlocked())),
      if (positionStream != null)
        currentPositionProvider.overrideWith((_) => positionStream),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MapScreen(),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('AC2 cache hit', () {
    testWidgets(
      'tap → flies to cached accurate fix; analytics outcome=recentered_from_cache',
      (tester) async {
        final renderer = FakeMapRenderer();
        final loc = FakeLocationService(
          checkPermissionResult: LocationPermission.whileInUse,
        );
        final analytics = RecordingAnalyticsService();
        final cached = fakePos(lat: 10.31, lng: 123.88, accuracy: 20);

        await pumpMap(
          tester,
          renderer: renderer,
          locationService: loc,
          analytics: analytics,
          positionStream: Stream.value(cached),
        );

        await tester.tap(find.byType(RecenterButton));
        await tester.pump();
        await tester.pump();

        expect(renderer.cameraTargetHistory, isNotEmpty);
        final last = renderer.cameraTargetHistory.last;
        expect(last.lat, 10.31);
        expect(last.lng, 123.88);
        expect(last.zoom, 17);

        expect(analytics.events, hasLength(1));
        expect(analytics.events.first.event, 'map.recenter.tapped');
        expect(
          analytics.events.first.properties,
          {'outcome': 'recentered_from_cache', 'accuracy_m': 20},
        );
      },
    );
  });
}
```

- [ ] **Step 2: Run, expect FAIL**

```bash
flutter test test/features/map/map_screen_recenter_test.dart
```

Expected: FAIL — `RecenterButton` isn't mounted yet, and `_onRecenterTap` doesn't exist.

- [ ] **Step 3: Wire `RecenterButton` and the happy-path orchestration**

Add imports to `lib/features/map/presentation/map_screen.dart`:

```dart
import 'package:firecheck/core/analytics/analytics_providers.dart';
import 'package:firecheck/features/map/presentation/recenter_button.dart';
import 'package:firecheck/features/map/presentation/recenter_button_state.dart';
```

Add the orchestration state to `_MapScreenState`:

```dart
class _MapScreenState extends ConsumerState<MapScreen> {
  bool _addModeActive = false;
  RecenterButtonState _recenterState = RecenterButtonState.idle;
  CameraTarget? _cameraTarget;
  int _recenterRequestSeq = 0;
  bool _rationaleVisible = false;
  // ... existing build, _handleLongPress, _handleFeatureTap, etc unchanged ...
```

Pass `cameraTarget: _cameraTarget` into the renderer (alongside the existing `initialCameraTarget`):

```dart
renderer.build(
  context,
  features: features,
  boundaryGeojson: assignment.boundaryPolygonGeojson,
  onFeatureTap: _handleFeatureTap,
  onLongPress: _handleLongPress,
  addModeActive: _addModeActive,
  initialCameraTarget: initialCameraTarget,
  cameraTarget: _cameraTarget,
)
```

Mount the button in the existing `Stack` (alongside the bottom pill row), before the closing `]` of the Stack's children:

```dart
Positioned(
  right: 16,
  bottom: 84,
  child: RecenterButton(
    state: _recenterState,
    onTap: _onRecenterTap,
  ),
),
```

Add the orchestration method (happy path only — slow path / errors come in later tasks):

```dart
Future<void> _onRecenterTap() async {
  if (_recenterState != RecenterButtonState.idle) return;
  if (_rationaleVisible) return;

  final seq = ++_recenterRequestSeq;
  final analytics = ref.read(analyticsServiceProvider);
  final locationService = ref.read(locationServiceProvider);

  final perm = await locationService.checkPermission();
  if (perm != LocationPermission.whileInUse &&
      perm != LocationPermission.always) {
    // Branches handled in later tasks (rationale, deniedForever).
    return;
  }

  if (seq != _recenterRequestSeq) return;

  final cached = ref.read(currentPositionProvider).valueOrNull;
  if (cached != null && cached.accuracy <= 100.0) {
    _flyTo(cached, seq: seq);
    analytics.track('map.recenter.tapped', properties: {
      'outcome': 'recentered_from_cache',
      'accuracy_m': cached.accuracy.round(),
    });
    return;
  }

  // Slow path — added in Task 12.
}

void _flyTo(Position p, {required int seq}) {
  setState(() {
    _cameraTarget = CameraTarget(
      lat: p.latitude,
      lng: p.longitude,
      zoom: 17,
      requestId: seq,
    );
  });
}
```

Add the `Position` import at the top of `map_screen.dart` if it isn't already there (it is — `geolocator/geolocator.dart` is imported at line 19).

- [ ] **Step 4: Run, expect PASS**

```bash
flutter test test/features/map/map_screen_recenter_test.dart
flutter test
```

Expected: PASS for both — new test green and no regressions.

- [ ] **Step 5: Commit**

```bash
git add lib/features/map/presentation/map_screen.dart test/features/map/map_screen_recenter_test.dart
git commit -m "feat(map): mount RecenterButton + cache-hit recenter (AC2 fast path)"
```

---

## Task 12: Slow path — wait for accurate fix (AC2 slow path)

**Files:**
- Modify: `lib/features/map/presentation/map_screen.dart`
- Modify: `test/features/map/map_screen_recenter_test.dart`

When no cached fix exists (or it's worse than 100 m), subscribe to `positionStream()` directly, take the first emission with `accuracy ≤ 100 m`, with an 8 s timeout. Show the loading spinner during the wait.

- [ ] **Step 1: Add the failing test**

Append a new group to `test/features/map/map_screen_recenter_test.dart`:

```dart
group('AC2 slow path', () {
  testWidgets(
    'no cached fix; stream emits poor then accurate → flies + analytics',
    (tester) async {
      final renderer = FakeMapRenderer();
      final controller = StreamController<Position>();
      final loc = FakeLocationService(
        checkPermissionResult: LocationPermission.whileInUse,
        positions: controller.stream,
      );
      final analytics = RecordingAnalyticsService();

      await pumpMap(
        tester,
        renderer: renderer,
        locationService: loc,
        analytics: analytics,
        positionStream: const Stream<Position>.empty(),
      );

      await tester.tap(find.byType(RecenterButton));
      await tester.pump();
      // The button should now be in loading state.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Emit a poor fix — should not satisfy the predicate.
      controller.add(fakePos(lat: 10.0, lng: 123.0, accuracy: 250));
      await tester.pump();
      expect(renderer.cameraTargetHistory, isEmpty);

      // Emit an accurate fix — orchestration takes it.
      controller.add(fakePos(lat: 10.5, lng: 123.5, accuracy: 30));
      await tester.pump();
      await tester.pump();

      expect(renderer.cameraTargetHistory, hasLength(1));
      expect(renderer.cameraTargetHistory.first.lat, 10.5);
      expect(analytics.events.first.properties, {
        'outcome': 'recentered_after_wait',
        'accuracy_m': 30,
      });
      // Button is back to idle (icon visible).
      expect(find.byIcon(Icons.my_location), findsOneWidget);

      await controller.close();
    },
  );
});
```

- [ ] **Step 2: Run, expect FAIL**

```bash
flutter test test/features/map/map_screen_recenter_test.dart
```

Expected: FAIL — slow path isn't implemented; the button stays idle and nothing happens.

- [ ] **Step 3: Add the slow path to `_onRecenterTap`**

Replace the trailing `// Slow path — added in Task 12.` comment with the slow-path body:

```dart
setState(() => _recenterState = RecenterButtonState.loading);

try {
  final accurate = await locationService
      .positionStream()
      .firstWhere((p) => p.accuracy <= 100.0)
      .timeout(const Duration(seconds: 8));

  if (!mounted || seq != _recenterRequestSeq) return;
  _flyTo(accurate, seq: seq);
  analytics.track('map.recenter.tapped', properties: {
    'outcome': 'recentered_after_wait',
    'accuracy_m': accurate.accuracy.round(),
  });
} on TimeoutException {
  // Handled in Task 13.
} finally {
  if (mounted && seq == _recenterRequestSeq) {
    setState(() => _recenterState = RecenterButtonState.idle);
  }
}
```

Add the `dart:async` import at the top:

```dart
import 'dart:async';
```

(Already imported at line 1 — verify before duplicating.)

- [ ] **Step 4: Run, expect PASS**

```bash
flutter test test/features/map/map_screen_recenter_test.dart
flutter test
```

Expected: PASS for both.

- [ ] **Step 5: Commit**

```bash
git add lib/features/map/presentation/map_screen.dart test/features/map/map_screen_recenter_test.dart
git commit -m "feat(map): slow-path recenter waits for ≤100m accuracy fix (AC2/AC7)"
```

---

## Task 13: 8s timeout — best-effort recenter + low-accuracy snackbar (AC6)

**Files:**
- Modify: `lib/features/map/presentation/map_screen.dart`
- Modify: `test/features/map/map_screen_recenter_test.dart`

When the slow path's `firstWhere` times out, show the `locationSnackbarLowAccuracy` snackbar, recenter best-effort to the most recent stream value (if any), and fire the `low_accuracy_timeout` analytics event.

- [ ] **Step 1: Add the failing test**

Append to `test/features/map/map_screen_recenter_test.dart`:

```dart
group('AC6/AC7 timeout', () {
  testWidgets(
    'stream emits only poor fixes → after 8s, best-effort recenter + warning',
    (tester) async {
      final renderer = FakeMapRenderer();
      final controller = StreamController<Position>();
      final poor = fakePos(lat: 10.0, lng: 123.0, accuracy: 250);
      final loc = FakeLocationService(
        checkPermissionResult: LocationPermission.whileInUse,
        positions: controller.stream,
      );
      final analytics = RecordingAnalyticsService();

      await pumpMap(
        tester,
        renderer: renderer,
        locationService: loc,
        analytics: analytics,
        positionStream: Stream.value(poor),
      );

      await tester.tap(find.byType(RecenterButton));
      await tester.pump();
      controller.add(poor);
      await tester.pump();

      // Advance past the 8s timeout.
      await tester.pump(const Duration(seconds: 9));
      await tester.pump();

      expect(
        find.text('Location accuracy is low. Showing your approximate position.'),
        findsOneWidget,
      );
      expect(renderer.cameraTargetHistory, hasLength(1));
      expect(renderer.cameraTargetHistory.first.lat, 10.0);
      expect(analytics.events.last.properties, {
        'outcome': 'low_accuracy_timeout',
        'accuracy_m': 250,
      });
      expect(find.byIcon(Icons.my_location), findsOneWidget);

      await controller.close();
    },
  );
});
```

- [ ] **Step 2: Run, expect FAIL**

```bash
flutter test test/features/map/map_screen_recenter_test.dart
```

Expected: FAIL — the timeout branch doesn't emit anything yet.

- [ ] **Step 3: Implement the timeout branch**

Replace the empty `on TimeoutException { ... }` block in `_onRecenterTap` with:

```dart
} on TimeoutException {
  if (!mounted || seq != _recenterRequestSeq) return;
  final best = ref.read(currentPositionProvider).valueOrNull;
  if (best != null) _flyTo(best, seq: seq);
  _showLowAccuracySnackbar();
  analytics.track('map.recenter.tapped', properties: {
    'outcome': 'low_accuracy_timeout',
    'accuracy_m': best?.accuracy.round(),
  });
}
```

Add the helper at the bottom of `_MapScreenState`:

```dart
void _showLowAccuracySnackbar() {
  if (!mounted) return;
  final l = AppLocalizations.of(context)!;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(l.locationSnackbarLowAccuracy)),
  );
}
```

- [ ] **Step 4: Run, expect PASS**

```bash
flutter test test/features/map/map_screen_recenter_test.dart
flutter test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/map/presentation/map_screen.dart test/features/map/map_screen_recenter_test.dart
git commit -m "feat(map): low-accuracy timeout → best-effort recenter + warning (AC6)"
```

---

## Task 14: `deniedForever` permission — settings-shortcut snackbar (AC5)

**Files:**
- Modify: `lib/features/map/presentation/map_screen.dart`
- Modify: `test/features/map/map_screen_recenter_test.dart`

- [ ] **Step 1: Add the failing test**

Append to `test/features/map/map_screen_recenter_test.dart`:

```dart
group('AC5 deniedForever', () {
  testWidgets(
    'tap → snackbar with Open settings; tap action → openAppSettingsCalled',
    (tester) async {
      final renderer = FakeMapRenderer();
      final loc = FakeLocationService(
        checkPermissionResult: LocationPermission.deniedForever,
      );
      final analytics = RecordingAnalyticsService();

      await pumpMap(
        tester,
        renderer: renderer,
        locationService: loc,
        analytics: analytics,
        positionStream: const Stream<Position>.empty(),
      );

      await tester.tap(find.byType(RecenterButton));
      await tester.pump();

      expect(
        find.text('Location permission denied. Open settings to enable it.'),
        findsOneWidget,
      );
      expect(renderer.cameraTargetHistory, isEmpty);
      expect(analytics.events.last.properties, {
        'outcome': 'permission_denied_forever',
      });

      await tester.tap(find.text('Open settings'));
      await tester.pump();
      expect(loc.openAppSettingsCalled, isTrue);
    },
  );
});
```

- [ ] **Step 2: Run, expect FAIL**

```bash
flutter test test/features/map/map_screen_recenter_test.dart
```

Expected: FAIL — no snackbar shown for `deniedForever` yet.

- [ ] **Step 3: Implement the deniedForever branch**

Replace the existing permission-gate block in `_onRecenterTap`:

```dart
final perm = await locationService.checkPermission();
if (perm != LocationPermission.whileInUse &&
    perm != LocationPermission.always) {
  // Branches handled in later tasks (rationale, deniedForever).
  return;
}
```

with:

```dart
var perm = await locationService.checkPermission();

// Rationale + OS prompt path lands in Task 15. For now, treat plain
// `denied` the same as deniedForever — bail without a snackbar but
// also without a fly. (Behavior tightened in Task 15.)

if (perm == LocationPermission.deniedForever ||
    perm == LocationPermission.unableToDetermine) {
  _showSettingsShortcutSnackbar(locationService);
  analytics.track('map.recenter.tapped', properties: {
    'outcome': 'permission_denied_forever',
  });
  return;
}
if (perm != LocationPermission.whileInUse &&
    perm != LocationPermission.always) {
  return; // tightened in Task 15
}
```

Add the helper at the bottom of `_MapScreenState`:

```dart
void _showSettingsShortcutSnackbar(LocationService locationService) {
  if (!mounted) return;
  final l = AppLocalizations.of(context)!;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(l.locationSnackbarPermanentlyDenied),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: l.locationSnackbarOpenSettings,
        onPressed: () => locationService.openAppSettings(),
      ),
    ),
  );
}
```

(Add the `LocationService` import to `map_screen.dart` if not already present: `import 'package:firecheck/core/location/location_service.dart';`.)

- [ ] **Step 4: Run, expect PASS**

```bash
flutter test test/features/map/map_screen_recenter_test.dart
flutter test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/map/presentation/map_screen.dart test/features/map/map_screen_recenter_test.dart
git commit -m "feat(map): deniedForever → snackbar with Open Settings shortcut (AC5)"
```

---

## Task 15: Rationale dialog — "Allow" path (AC4 happy)

**Files:**
- Modify: `lib/features/map/presentation/map_screen.dart`
- Modify: `test/features/map/map_screen_recenter_test.dart`

When `checkPermission()` returns `denied`, show the rationale dialog. If the user taps "Allow", call `requestPermission()` and continue based on the post-prompt result.

- [ ] **Step 1: Add the failing test**

Append to `test/features/map/map_screen_recenter_test.dart`:

```dart
group('AC4 rationale → allow', () {
  testWidgets(
    'denied → rationale dialog → Allow → requestPermission → recenter on cache',
    (tester) async {
      final renderer = FakeMapRenderer();
      final loc = FakeLocationService(
        checkPermissionResult: LocationPermission.denied,
        requestPermissionResult: LocationPermission.whileInUse,
      );
      final analytics = RecordingAnalyticsService();
      final cached = fakePos(lat: 10.31, lng: 123.88, accuracy: 25);

      await pumpMap(
        tester,
        renderer: renderer,
        locationService: loc,
        analytics: analytics,
        positionStream: Stream.value(cached),
      );

      await tester.tap(find.byType(RecenterButton));
      await tester.pump();

      // Rationale dialog is up.
      expect(find.text('Use your location'), findsOneWidget);
      expect(find.text('Allow'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);

      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();

      expect(renderer.cameraTargetHistory, hasLength(1));
      expect(analytics.events.last.properties, {
        'outcome': 'recentered_from_cache',
        'accuracy_m': 25,
      });
    },
  );
});
```

- [ ] **Step 2: Run, expect FAIL**

```bash
flutter test test/features/map/map_screen_recenter_test.dart
```

Expected: FAIL — no rationale dialog shown.

- [ ] **Step 3: Implement the rationale dialog**

Replace the `// Rationale + OS prompt path lands in Task 15.` comment block (above the `deniedForever` check) with:

```dart
if (perm == LocationPermission.denied) {
  final allow = await _showLocationRationale();
  if (allow != true) {
    analytics.track('map.recenter.tapped', properties: {
      'outcome': 'permission_rationale_dismissed',
    });
    return;
  }
  perm = await locationService.requestPermission();
}
```

Tighten the post-permission check (replace the trailing `if (perm != ... whileInUse && ... always) { return; // tightened in Task 15 }` block) with:

```dart
if (perm == LocationPermission.denied) {
  analytics.track('map.recenter.tapped', properties: {
    'outcome': 'permission_denied',
  });
  return;
}
```

Add the rationale-dialog helper at the bottom of `_MapScreenState`:

```dart
Future<bool?> _showLocationRationale() async {
  if (!mounted) return null;
  _rationaleVisible = true;
  try {
    final l = AppLocalizations.of(context)!;
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l.locationRationaleTitle),
        content: Text(l.locationRationaleBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(l.locationRationaleNotNow),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(l.locationRationaleAllow),
          ),
        ],
      ),
    );
  } finally {
    _rationaleVisible = false;
  }
}
```

- [ ] **Step 4: Run, expect PASS**

```bash
flutter test test/features/map/map_screen_recenter_test.dart
flutter test
```

Expected: PASS — new test green; previous AC4 dummy-bail behavior is now properly implemented.

- [ ] **Step 5: Commit**

```bash
git add lib/features/map/presentation/map_screen.dart test/features/map/map_screen_recenter_test.dart
git commit -m "feat(map): rationale dialog → Allow → requestPermission flow (AC4)"
```

---

## Task 16: Rationale dialog — "Not now" path (AC4 dismiss)

**Files:**
- Modify: `test/features/map/map_screen_recenter_test.dart`

The implementation already handles "Not now" (Task 15's `if (allow != true) { ... return; }`). This task adds the test that pins the behavior so a future refactor can't quietly drop the analytics event.

- [ ] **Step 1: Add the test**

Append to `test/features/map/map_screen_recenter_test.dart`:

```dart
group('AC4 rationale → Not now', () {
  testWidgets(
    'denied → rationale dialog → Not now → no requestPermission, no fly',
    (tester) async {
      final renderer = FakeMapRenderer();
      final loc = FakeLocationService(
        checkPermissionResult: LocationPermission.denied,
        // requestPermissionResult is irrelevant — should not be called.
        requestPermissionResult: LocationPermission.whileInUse,
      );
      final analytics = RecordingAnalyticsService();

      await pumpMap(
        tester,
        renderer: renderer,
        locationService: loc,
        analytics: analytics,
        positionStream: const Stream<Position>.empty(),
      );

      await tester.tap(find.byType(RecenterButton));
      await tester.pump();

      expect(find.text('Use your location'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(renderer.cameraTargetHistory, isEmpty);
      expect(analytics.events.last.properties, {
        'outcome': 'permission_rationale_dismissed',
      });
    },
  );
});
```

- [ ] **Step 2: Run, expect PASS (already implemented)**

```bash
flutter test test/features/map/map_screen_recenter_test.dart
```

Expected: PASS — Task 15's implementation already covers this branch; this commit pins it with a regression test.

- [ ] **Step 3: Commit**

```bash
git add test/features/map/map_screen_recenter_test.dart
git commit -m "test(map): pin rationale Not-now path (AC4 dismiss)"
```

---

## Task 17: Final regression + manual QA checklist

**Files:**
- (no code changes)

Confirm the whole feature works end-to-end before handing off.

- [ ] **Step 1: Run analyze on the whole repo**

```bash
flutter analyze
```

Expected: "No issues found!" Fix any warnings introduced; do NOT silence them with `// ignore:` unless the underlying issue is platform/SDK-driven and documented in a comment.

- [ ] **Step 2: Run the full test suite**

```bash
flutter test
```

Expected: ALL tests pass, including the existing `map_screen_test.dart`, `map_screen_add_mode_test.dart`, integration tests, etc.

- [ ] **Step 3: Manual smoke (recommended on a real device or emulator)**

Build and run on Android first (faster cycle), then iOS:

```bash
flutter run
```

Verify in order:
1. **Initial frame**: app opens to the map → camera is centered on the assignment boundary, not the hard-coded Cebu point.
2. **First recenter tap (fresh install)**: rationale dialog appears → tap "Allow" → OS prompt → grant → puck appears, map flies in. Confirm `[analytics] map.recenter.tapped {"outcome":"recentered_..."}` printed in console.
3. **Repeated tap with permission granted**: cache hit, immediate fly, no spinner.
4. **Indoor / poor GPS**: tap recenter → spinner shows → after ≤8 s, low-accuracy snackbar appears + best-effort fly (or no fly if no fix at all).
5. **Settings off + tap recenter**: turn off "While using app" in OS settings → return → tap recenter → snackbar with "Open settings" → tap action → confirm settings page opens.
6. **Battery sanity**: leave the screen idle for ~5 min after a recenter; OS profiler / Geolocator logs should show GPS quiescent (only 3 m-distanceFilter ticks at most).
7. **Add-mode interaction**: enable add mode → confirm recenter button still tappable; tap it → camera flies; add-mode pill remains active.
8. **Existing flows**: tap a feature polygon → detail screen opens → return → camera is preserved (no unexpected re-frame).

- [ ] **Step 4: Confirm DoD bullets**

Re-read `docs/superpowers/specs/2026-04-28-recenter-map-design.md` §5 "Acceptance criteria mapping" and §6.3 "Manual / device QA — Definition of Done". Tick every box. If a manual-only test (AC3 puck visibility, AC8 offline behavior) was deferred for some reason, document it in the PR description.

- [ ] **Step 5: Push the branch and open a PR**

```bash
git push -u origin 12-as-an-enumerator-i-want-a-button-to-recenter-the-map-on-my-current-gps-location-so-that-i-can-quickly-orient-myself-in-the-field
gh pr create --title "feat(map): recenter button on map screen (US-12)" --body "$(cat <<'EOF'
## Summary

- Adds a circular `RecenterButton` to the bottom-right of the map screen.
- Cached-if-accurate fast path; 8s wait + best-effort fallback for poor GPS.
- Rationale-then-OS-prompt permission flow; deniedForever snackbar with settings shortcut.
- Replaces hard-coded Cebu fallback with assignment-boundary-derived initial framing.
- Adds minimal `AnalyticsService` stub (no-op default, console-logger in debug builds).
- Removes dead Follow-me pill and on-mount permission kick.

## Test plan

- [ ] `flutter analyze` clean
- [ ] `flutter test` green
- [ ] Manual QA on Android (rationale, deny, deniedForever, indoor, settings-roundtrip)
- [ ] Manual QA on iOS (same)
- [ ] Battery profiler: idle 5 min after a recenter shows GPS quiescent

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 6: Final commit (only if `flutter gen-l10n` regenerated stale generated files during testing)**

```bash
git status
# If generated/l10n is dirty:
git add lib/generated/l10n/
git commit -m "chore: regenerate localizations"
```

---

## Spec coverage check

| Spec section | Covered by |
|---|---|
| §2 In-scope item: `RecenterButton` widget | Task 6 |
| §2 In-scope item: `CameraTarget` value type | Task 4 |
| §2 In-scope item: `MapRenderer.build()` signature change | Task 8 |
| §2 In-scope item: Initial camera framing from boundary | Tasks 3 + 10 |
| §2 In-scope item: `_onRecenterTap` orchestration | Tasks 11–16 |
| §2 In-scope item: `LocationService` interface changes | Task 7 |
| §2 In-scope item: Rationale dialog (AC4) | Tasks 15–16 |
| §2 In-scope item: deniedForever snackbar (AC5) | Task 14 |
| §2 In-scope item: `AnalyticsService` stub | Tasks 1–2 |
| §2 In-scope item: Delete dead Follow-me pill | Task 9 |
| §2 In-scope item: i18n keys | Task 5 |
| §5 AC1 placement | Task 11 (visually verified) + Task 17 manual QA |
| §5 AC2 recenter on tap | Tasks 11 + 12 |
| §5 AC3 location indicator | Pre-existing `LocationComponentSettings`; Task 17 manual QA |
| §5 AC4 permission not granted | Tasks 15 + 16 |
| §5 AC5 permission denied permanently | Task 14 |
| §5 AC6 GPS unavailable / weak signal | Task 13 |
| §5 AC7 loading state | Tasks 11 (button) + 12 (set on slow path) |
| §5 AC8 offline behavior | Task 17 manual QA only |
| §5 AC9 battery efficiency | No code (existing infra); Task 17 manual QA |

Every in-scope item and every AC has at least one task referencing it.
