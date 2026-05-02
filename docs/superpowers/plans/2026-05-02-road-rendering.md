# Road Feature Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render road features as 8 px coloured polylines on the map, make them tappable to open the road survey form, and fix the `markFeatureStatus` bug so road status updates propagate to line colour without a full map reload.

**Architecture:** `decodePolylineGeojson` (already exists in `lib/core/geo/polyline_midpoint.dart`) is used by a new `_decodeLineString()` method on `_MapboxMapViewState` to convert GeoJSON into Mapbox `Position` lists. A new `_roadManager` (`PolylineAnnotationManager`) renders road lines alongside existing building polygon managers. `markFeatureStatus` is patched to branch on `featureType` so road attributes are checked instead of building attributes.

**Tech Stack:** Flutter, Drift (SQLite), `mapbox_maps_flutter` 2.22, Riverpod, GoRouter

---

## File Map

| Action | File |
|--------|------|
| Modify | `lib/core/geo/polyline_midpoint.dart` |
| Modify | `lib/features/map/data/feature_repository.dart` |
| Modify | `lib/features/map/presentation/map_renderer.dart` |
| Modify | `test/core/geo/polyline_midpoint_test.dart` |
| Modify | `test/features/map/feature_repository_test.dart` |
| Create | `test/features/map/map_screen_road_test.dart` |

---

### Task 1: Add missing edge-case tests for `decodePolylineGeojson` + fix

`decodePolylineGeojson` currently returns a non-null single-element list for a LineString with 1 coordinate — a degenerate case that `_decodeLineString` will treat as valid. This task adds the failing test and the one-line fix.

**Files:**
- Modify: `test/core/geo/polyline_midpoint_test.dart`
- Modify: `lib/core/geo/polyline_midpoint.dart`

- [ ] **Step 1: Write the failing test**

Add inside `void main()` in `test/core/geo/polyline_midpoint_test.dart`:

```dart
test('returns null for LineString with fewer than 2 coordinates', () {
  final coords = decodePolylineGeojson(
    '{"type":"LineString","coordinates":[[123.882,10.317]]}',
  );
  expect(coords, isNull);
});

test('returns null for LineString with empty coordinates', () {
  final coords = decodePolylineGeojson(
    '{"type":"LineString","coordinates":[]}',
  );
  expect(coords, isNull);
});
```

- [ ] **Step 2: Run the new tests to verify they fail**

```
flutter test test/core/geo/polyline_midpoint_test.dart -v
```

Expected: 2 failures — `expected: null  actual: [[...]]` and `expected: null  actual: []`

- [ ] **Step 3: Add the length check to `decodePolylineGeojson`**

In `lib/core/geo/polyline_midpoint.dart`, after the `if (parsed['type'] != 'LineString') return null;` line (line 49), add:

```dart
if (coords.length < 2) return null;
```

Full updated function:

```dart
List<List<double>>? decodePolylineGeojson(String geojson) {
  try {
    final parsed = jsonDecode(geojson) as Map<String, dynamic>;
    if (parsed['type'] != 'LineString') return null;
    final coords = parsed['coordinates'] as List<dynamic>;
    if (coords.length < 2) return null;
    return coords
        .map(
          (p) =>
              (p as List<dynamic>).map((v) => (v as num).toDouble()).toList(),
        )
        .toList();
  } on Object {
    return null;
  }
}
```

- [ ] **Step 4: Run all tests in the file to verify all pass**

```
flutter test test/core/geo/polyline_midpoint_test.dart -v
```

Expected: 6 passed, 0 failed

- [ ] **Step 5: Commit**

```bash
git add test/core/geo/polyline_midpoint_test.dart lib/core/geo/polyline_midpoint.dart
git commit -m "fix(geo): decodePolylineGeojson returns null for < 2 coords"
```

---

### Task 2: Fix `markFeatureStatus` for road features + tests

`markFeatureStatus` always queries `buildingAttributes`, so road features with saved road attributes stay `'unfilled'` instead of advancing to `'in_progress'`. This task fixes the branch and adds regression tests.

**Files:**
- Modify: `test/features/map/feature_repository_test.dart`
- Modify: `lib/features/map/data/feature_repository.dart`

- [ ] **Step 1: Write the failing test**

Add inside the `group('markFeatureStatus', ...)` block in `test/features/map/feature_repository_test.dart`:

```dart
test('road feature with a draft + road_attributes is in_progress', () async {
  final now = DateTime.now();
  await db.into(db.features).insert(
    FeaturesCompanion.insert(
      id: 'f1',
      assignmentId: 'a1',
      featureType: 'road',
      geometryGeojson: '{"type":"LineString","coordinates":[[120.0,14.0],[121.0,14.5]]}',
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
  await db.into(db.roadAttributes).insert(
    RoadAttributesCompanion.insert(
      submissionId: 's1',
      roadName: const Value('Main St'),
    ),
  );
  await repo.markFeatureStatus('f1');
  final f = (await db.select(db.features).get()).single;
  expect(f.status, 'in_progress');
});

test('road feature with a ready_to_upload submission is complete', () async {
  final now = DateTime.now();
  await db.into(db.features).insert(
    FeaturesCompanion.insert(
      id: 'f1',
      assignmentId: 'a1',
      featureType: 'road',
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
```

- [ ] **Step 2: Run the new tests to verify they fail**

```
flutter test test/features/map/feature_repository_test.dart -v
```

Expected: `road feature with a draft + road_attributes is in_progress` FAILS with `expected: 'in_progress'  actual: 'unfilled'`; `road feature with a ready_to_upload submission is complete` PASSES (syncStatus check is already correct).

- [ ] **Step 3: Fix `markFeatureStatus` to branch on `featureType`**

Replace the entire `markFeatureStatus` method in `lib/features/map/data/feature_repository.dart` with:

```dart
Future<void> markFeatureStatus(String featureId) async {
  final feature = await getFeature(featureId);
  if (feature == null) return;

  final submissions = await (_db.select(_db.submissions)
        ..where((t) => t.featureId.equals(featureId)))
      .get();

  var status = 'unfilled';

  final anyComplete = submissions.any(
    (s) =>
        s.syncStatus == 'ready_to_upload' ||
        s.syncStatus == 'queued' ||
        s.syncStatus == 'uploaded',
  );
  if (anyComplete) {
    status = 'complete';
  } else if (submissions.isNotEmpty) {
    final attrIds = submissions.map((s) => s.id).toList();
    final bool anyAttrs;
    if (feature.featureType == 'road') {
      final attrs = await (_db.select(_db.roadAttributes)
            ..where((t) => t.submissionId.isIn(attrIds)))
          .get();
      anyAttrs = attrs.isNotEmpty;
    } else {
      final attrs = await (_db.select(_db.buildingAttributes)
            ..where((t) => t.submissionId.isIn(attrIds)))
          .get();
      anyAttrs = attrs.isNotEmpty;
    }
    final anyInProgress = anyAttrs || submissions.any((s) => s.doesNotExist);
    if (anyInProgress) status = 'in_progress';
  }

  await (_db.update(_db.features)..where((t) => t.id.equals(featureId)))
      .write(FeaturesCompanion(status: Value(status)));
}
```

- [ ] **Step 4: Run the full feature_repository_test.dart to verify all pass**

```
flutter test test/features/map/feature_repository_test.dart -v
```

Expected: all tests pass

- [ ] **Step 5: Commit**

```bash
git add test/features/map/feature_repository_test.dart lib/features/map/data/feature_repository.dart
git commit -m "fix(map): markFeatureStatus checks roadAttributes for road features"
```

---

### Task 3: Add `_roadManager`, `_renderRoads()`, and `_RoadClickHandler` to `MapboxMapRenderer`

This task wires road line rendering into `_MapboxMapViewState`. No unit tests target this class directly (Mapbox doesn't render in `flutter_tester`); widget tests in Task 4 exercise the `FakeMapRenderer` path instead.

**Files:**
- Modify: `lib/features/map/presentation/map_renderer.dart`

- [ ] **Step 1: Add the `polyline_midpoint` import**

At the top of `lib/features/map/presentation/map_renderer.dart`, after the existing `firecheck/core/geo/point_in_polygon.dart` import (line 5), add:

```dart
import 'package:firecheck/core/geo/polyline_midpoint.dart';
```

- [ ] **Step 2: Add the `_roadManager` field to `_MapboxMapViewState`**

In `class _MapboxMapViewState extends State<_MapboxMapView>`, after the `PointAnnotationManager? _pointManager;` field declaration (line 238), add:

```dart
PolylineAnnotationManager? _roadManager;
```

- [ ] **Step 3: Skip road features in `_renderFeatures()`**

In the `_renderFeatures()` method (line 533), after the `if (f.isNew) continue;` line (line 539), add:

```dart
if (f.featureType == 'road') continue;
```

The method body now reads:

```dart
Future<void> _renderFeatures() async {
  final manager = _featureManager;
  if (manager == null) return;
  for (final f in widget.features) {
    if (f.isNew) continue;
    if (f.featureType == 'road') continue;
    final polygon = _decodePolygon(f.geometryGeojson);
    if (polygon == null) continue;
    final created = await manager.create(
      PolygonAnnotationOptions(
        geometry: polygon,
        fillColor: _colorForStatus(f.status),
        fillOpacity: 0.4,
      ),
    );
    _annotationToFeature[created.id] = f;
  }
}
```

- [ ] **Step 4: Add `_decodeLineString()` and `_renderRoads()` methods**

After the `_renderBoundary()` method (ends around line 570), add:

```dart
Future<void> _renderRoads() async {
  final manager = _roadManager;
  if (manager == null) return;
  for (final f in widget.features) {
    if (f.isNew) continue;
    if (f.featureType != 'road') continue;
    final coords = _decodeLineString(f.geometryGeojson);
    if (coords == null) {
      debugPrint(
        '[MapRenderer] skipped road feature ${f.id}: invalid LineString geometry',
      );
      continue;
    }
    final created = await manager.create(
      PolylineAnnotationOptions(
        geometry: LineString(coordinates: coords),
        lineColor: _colorForStatus(f.status),
        lineWidth: 8.0,
      ),
    );
    _annotationToFeature[created.id] = f;
  }
}

List<Position>? _decodeLineString(String geojson) {
  final coords = decodePolylineGeojson(geojson);
  if (coords == null) return null;
  return coords.map((p) => Position(p[0], p[1])).toList();
}
```

- [ ] **Step 5: Update `_onMapCreated` to create the road manager, render roads, and register the tap listener**

In `_onMapCreated` (line 334):

a. After `_pointManager = await map.annotations.createPointAnnotationManager();` (line 373), add:

```dart
_roadManager = await map.annotations.createPolylineAnnotationManager();
```

b. After `await _renderFeatures();` (line 376), add:

```dart
await _renderRoads();
```

c. After the `_featureManager!.addOnPolygonAnnotationClickListener(...)` block (ends around line 385), add:

```dart
// ignore: deprecated_member_use
_roadManager!.addOnPolylineAnnotationClickListener(
  _RoadClickHandler(
    annotationToFeature: _annotationToFeature,
    onTap: widget.onFeatureTap,
  ),
);
```

- [ ] **Step 6: Update `_rerenderFeatures()` to clear and re-render roads**

In `_rerenderFeatures()` (line 493):

a. After `await manager.deleteAll();` (line 496), add:

```dart
await _roadManager?.deleteAll();
```

b. After `await _renderFeatures();` (line 499), add:

```dart
await _renderRoads();
```

c. After the `manager.addOnPolygonAnnotationClickListener(...)` block (ends around line 515), add:

```dart
// ignore: deprecated_member_use
_roadManager?.addOnPolylineAnnotationClickListener(
  _RoadClickHandler(
    annotationToFeature: _annotationToFeature,
    onTap: widget.onFeatureTap,
  ),
);
```

- [ ] **Step 7: Add the `_RoadClickHandler` class**

After the closing brace of `_FeatureClickHandler` (ends around line 661), add:

```dart
// ignore: deprecated_member_use
class _RoadClickHandler extends OnPolylineAnnotationClickListener {
  _RoadClickHandler({
    required this.annotationToFeature,
    required this.onTap,
  });

  final Map<String, Feature> annotationToFeature;
  final void Function(Feature) onTap;

  @override
  void onPolylineAnnotationClick(PolylineAnnotation annotation) {
    final feature = annotationToFeature[annotation.id];
    if (feature != null) onTap(feature);
  }
}
```

- [ ] **Step 8: Run `flutter analyze` and verify zero issues**

```
flutter analyze lib/features/map/presentation/map_renderer.dart
```

Expected: No issues found!

- [ ] **Step 9: Commit**

```bash
git add lib/features/map/presentation/map_renderer.dart
git commit -m "feat(map): add road polyline rendering with status colour and tap handler"
```

---

### Task 4: Widget tests for road rendering, tap, and colour update

These tests use `FakeMapRenderer` which renders all features (including roads) as tappable tiles with status-driven colours. `MapScreen` wires the tap to `_handleFeatureTap`, which navigates via GoRouter. The colour-update test uses a `StreamController` to emit an updated feature list.

**Files:**
- Create: `test/features/map/map_screen_road_test.dart`

- [ ] **Step 1: Create the test file with helpers**

```dart
import 'dart:async';

import 'package:drift/native.dart';
import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/map/presentation/map_providers.dart';
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:firecheck/features/map/presentation/map_screen.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Feature _roadFeature({String status = 'not_started'}) => Feature(
      id: 'r1',
      assignmentId: 'a1',
      featureType: 'road',
      geometryGeojson:
          '{"type":"LineString","coordinates":[[120.0,14.0],[121.0,14.5]]}',
      isNew: false,
      status: status,
      createdAt: DateTime.now(),
    );

final _stubAssignment = Assignment(
  id: 'a1',
  enumeratorId: 'e1',
  campaignId: 'c1',
  boundaryPolygonGeojson: '{}',
  status: 'assigned',
  closedRemotely: false,
  createdAt: DateTime.now(),
);

Widget _buildSubject({
  required Stream<List<Feature>> featuresStream,
  required AppDatabase db,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const MapScreen()),
      GoRoute(
        path: '/feature/:id',
        builder: (_, state) =>
            Scaffold(body: Text('survey-${state.pathParameters['id']}')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      mapRendererProvider.overrideWithValue(FakeMapRenderer()),
      currentFeaturesProvider.overrideWith((ref) => featuresStream),
      currentAssignmentProvider
          .overrideWith((ref) => Stream.value(_stubAssignment)),
      assignmentLockStateProvider
          .overrideWith((_) => Stream.value(const Unlocked())),
      currentUserIdProvider.overrideWith((ref) => 'u1'),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}
```

- [ ] **Step 2: Write the three tests**

Add `void main()` with setUp/tearDown and three tests:

```dart
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  testWidgets('road feature renders as a tappable tile', (tester) async {
    await tester.pumpWidget(_buildSubject(
      featuresStream: Stream.value([_roadFeature()]),
      db: db,
    ));
    await tester.pump();

    expect(find.byKey(const Key('fake-map-poly-r1')), findsOneWidget);
  });

  testWidgets('tapping road tile navigates to /feature/r1', (tester) async {
    final now = DateTime.now();
    await tester.runAsync(() async {
      await db.into(db.features).insert(FeaturesCompanion.insert(
        id: 'r1',
        assignmentId: 'a1',
        featureType: 'road',
        geometryGeojson:
            '{"type":"LineString","coordinates":[[120.0,14.0],[121.0,14.5]]}',
        createdAt: now,
      ));
    });

    await tester.pumpWidget(_buildSubject(
      featuresStream: Stream.value([_roadFeature()]),
      db: db,
    ));
    await tester.pump();

    await tester.tap(find.byKey(const Key('fake-map-feature-r1')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    expect(find.text('survey-r1'), findsOneWidget);
  });

  testWidgets('road tile colour updates when status changes to complete',
      (tester) async {
    final controller = StreamController<List<Feature>>();
    addTearDown(controller.close);

    await tester.pumpWidget(_buildSubject(
      featuresStream: controller.stream,
      db: db,
    ));

    controller.add([_roadFeature(status: 'not_started')]);
    await tester.pump();

    final redTile = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const Key('fake-map-feature-r1')),
        matching: find.byKey(const Key('fake-map-poly-r1')),
      ),
    );
    expect(redTile.color, const Color(0x66C53030));

    controller.add([_roadFeature(status: 'complete')]);
    await tester.pump();

    final greenTile = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const Key('fake-map-feature-r1')),
        matching: find.byKey(const Key('fake-map-poly-r1')),
      ),
    );
    expect(greenTile.color, const Color(0x66276749));
  });
}
```

- [ ] **Step 3: Run the new tests to verify they pass**

```
flutter test test/features/map/map_screen_road_test.dart -v
```

Expected: 3 passed, 0 failed

- [ ] **Step 4: Run the full test suite to verify no regressions**

```
flutter test --exclude-tags slow
```

Expected: all existing tests pass; 3 new road tests pass

- [ ] **Step 5: Run `flutter analyze` on the new test file**

```
flutter analyze test/features/map/map_screen_road_test.dart
```

Expected: No issues found!

- [ ] **Step 6: Commit**

```bash
git add test/features/map/map_screen_road_test.dart
git commit -m "test(map): widget tests for road tile rendering, tap navigation, and colour update"
```
