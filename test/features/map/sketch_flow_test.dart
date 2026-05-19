import 'dart:convert';

import 'package:drift/native.dart';
import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/location/location_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/map/geometry_editor/presentation/geometry_editor_providers.dart';
import 'package:firecheck/features/map/presentation/map_providers.dart';
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:firecheck/features/map/presentation/map_screen.dart';
import 'package:firecheck/features/remote_activity/presentation/remote_activity_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

// 10x10 boundary used by every test below, centred at origin-ish coords. Tests
// drop vertices inside (1..9) for in-bounds and outside for boundary failures.
const _boundary =
    '{"type":"Polygon","coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]]]}';

Assignment _assignment() => Assignment(
      id: 'a1',
      enumeratorId: 'admin',
      campaignId: 'c1',
      boundaryPolygonGeojson: _boundary,
      status: 'assigned',
      closedRemotely: false,
      createdAt: DateTime.utc(2026),
    );

/// Pumps MapScreen with a GoRouter that captures navigations to a sentinel
/// route, plus an in-memory Drift DB so `repo.createFeature` succeeds and we
/// can read back the inserted row.
Future<({ProviderContainer container, AppDatabase db, GoRouter router})>
    _pumpSketchHarness(
  WidgetTester tester, {
  required FakeMapRenderer renderer,
  List<Feature> features = const [],
}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  // Persist the assignment so createFeature's FK to assignments holds.
  await tester.runAsync(() async {
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'admin',
            campaignId: 'c1',
            boundaryPolygonGeojson: _boundary,
            createdAt: DateTime.now(),
          ),
        );
  });
  addTearDown(() => tester.runAsync(db.close));

  final router = GoRouter(
    initialLocation: '/map',
    routes: [
      GoRoute(path: '/map', builder: (_, __) => const MapScreen()),
      GoRoute(
        path: '/feature/:featureId',
        builder: (_, state) => Scaffold(
          key: const Key('feature-detail-sentinel'),
          body: Center(
            child: Text('feature-form-${state.pathParameters['featureId']}'),
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  final container = ProviderContainer(
    overrides: [
      mapRendererProvider.overrideWithValue(renderer),
      appDatabaseProvider.overrideWithValue(db),
      currentUserIdProvider.overrideWithValue('admin'),
      currentFeaturesProvider.overrideWith((_) => Stream.value(features)),
      currentAssignmentProvider.overrideWith((_) => Stream.value(_assignment())),
      assignmentLockStateProvider
          .overrideWith((_) => Stream.value(const Unlocked())),
      // Avoid the real geolocator plugin (MissingPluginException in widget
      // tests). MapScreen subscribes to currentPositionProvider on mount.
      currentPositionProvider.overrideWith((_) => const Stream<Position>.empty()),
      othersRemoteAttributionsProvider.overrideWith(
        (_) => Stream.value(const []),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return (container: container, db: db, router: router);
}

/// Opens the type picker via the +pill and taps the building/road option.
/// (Point isn't in the picker — those tests drive enterSketch directly.)
Future<void> _enterSketchViaPill(WidgetTester tester, String type) async {
  await tester.tap(find.byKey(const Key('map.add-feature-pill')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('feature-type-picker.$type')));
  await tester.pumpAndSettle();
}

void main() {
  group('sketch flow — Building', () {
    testWidgets('happy path: 3 vertices → Finish → navigate + Polygon row',
        (tester) async {
      final fake = FakeMapRenderer();
      final h = await _pumpSketchHarness(tester, renderer: fake);

      await _enterSketchViaPill(tester, 'building');

      await fake.simulateMapTap(1, 1);
      await fake.simulateMapTap(2, 1);
      await fake.simulateMapTap(2, 2);
      await tester.pump();

      // Banner reflects 3 vertices · building.
      expect(find.text('3 vertices · building'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reshape.banner.save')));
      // Pump a few frames for the async createFeature → push.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      // Routed to detail sentinel.
      expect(find.byKey(const Key('feature-detail-sentinel')), findsOneWidget);

      // DB has exactly one feature, polygon-shaped, closed ring.
      final rows = await tester.runAsync(() => h.db.select(h.db.features).get());
      expect(rows, hasLength(1));
      final f = rows!.first;
      expect(f.featureType, 'building');
      expect(f.isNew, isTrue);
      final geom = jsonDecode(f.geometryGeojson) as Map<String, dynamic>;
      expect(geom['type'], 'Polygon');
      final coords = (geom['coordinates'] as List).first as List;
      // Polygon should be closed (first == last).
      expect(coords.first, coords.last);
      // 3 unique + 1 closing = 4.
      expect(coords, hasLength(4));
    });

    testWidgets('vertex outside boundary → snackbar; state preserved',
        (tester) async {
      final fake = FakeMapRenderer();
      final h = await _pumpSketchHarness(tester, renderer: fake);

      await _enterSketchViaPill(tester, 'building');

      await fake.simulateMapTap(1, 1); // in
      await fake.simulateMapTap(2, 2); // in
      await fake.simulateMapTap(99, 99); // way outside
      await tester.pump();

      expect(find.text('3 vertices · building'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reshape.banner.save')));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      // Snackbar text comes from outsideBoundarySnackbar
      // ("Long-press is outside your assignment area").
      expect(find.textContaining('outside'), findsWidgets);
      // State preserved — banner still shows 3 vertices.
      expect(find.text('3 vertices · building'), findsOneWidget);
      // No DB row inserted.
      final rows = await tester.runAsync(() => h.db.select(h.db.features).get());
      expect(rows, isEmpty);
    });

    testWidgets('bowtie self-intersection → snackbar with "cross"',
        (tester) async {
      final fake = FakeMapRenderer();
      final h = await _pumpSketchHarness(tester, renderer: fake);

      await _enterSketchViaPill(tester, 'building');

      // Bowtie: (1,1) → (5,5) → (5,1) → (1,5). Edges 1-2 and 3-4 cross.
      await fake.simulateMapTap(1, 1);
      await fake.simulateMapTap(5, 5);
      await fake.simulateMapTap(1, 5);
      await fake.simulateMapTap(5, 1);
      await tester.pump();

      expect(find.text('4 vertices · building'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reshape.banner.save')));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.textContaining('cross'), findsWidgets);
      final rows = await tester.runAsync(() => h.db.select(h.db.features).get());
      expect(rows, isEmpty);
    });
  });

  group('sketch flow — Road', () {
    testWidgets('happy path: 2 vertices → Finish → navigate + LineString row',
        (tester) async {
      final fake = FakeMapRenderer();
      final h = await _pumpSketchHarness(tester, renderer: fake);

      await _enterSketchViaPill(tester, 'road');

      await fake.simulateMapTap(1, 1);
      await fake.simulateMapTap(3, 4);
      await tester.pump();

      expect(find.text('2 vertices · road'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reshape.banner.save')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('feature-detail-sentinel')), findsOneWidget);

      final rows = await tester.runAsync(() => h.db.select(h.db.features).get());
      expect(rows, hasLength(1));
      final f = rows!.first;
      expect(f.featureType, 'road');
      final geom = jsonDecode(f.geometryGeojson) as Map<String, dynamic>;
      expect(geom['type'], 'LineString');
      expect(geom['coordinates'], hasLength(2));
    });

    testWidgets('zero-length segment → snackbar', (tester) async {
      final fake = FakeMapRenderer();
      final h = await _pumpSketchHarness(tester, renderer: fake);

      await _enterSketchViaPill(tester, 'road');

      await fake.simulateMapTap(2, 2);
      await fake.simulateMapTap(2, 2); // identical → zero-length
      await tester.pump();

      expect(find.text('2 vertices · road'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reshape.banner.save')));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      // reshapeErrorZeroLengthEdge: "Adjacent corners cannot be on the same spot".
      expect(find.textContaining('same spot'), findsWidgets);
      final rows = await tester.runAsync(() => h.db.select(h.db.features).get());
      expect(rows, isEmpty);
    });
  });

  group('sketch flow — Point', () {
    // The type picker exposes only Building/Road; the Point branch is
    // exercised via the controller directly. The Finish/validate code path
    // in MapScreen is type-agnostic — all that matters is that
    // pendingFeatureType == 'point' is in state when Finish runs.
    testWidgets('happy path: 1 tap → Finish → navigate + Point row',
        (tester) async {
      final fake = FakeMapRenderer();
      final h = await _pumpSketchHarness(tester, renderer: fake);

      h.container
          .read(geometryEditorControllerProvider.notifier)
          .enterSketch(featureType: 'point');
      await tester.pump();

      await fake.simulateMapTap(3, 4); // (lat=3, lng=4)
      await tester.pump();

      expect(find.text('1 vertices · point'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reshape.banner.save')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('feature-detail-sentinel')), findsOneWidget);

      final rows = await tester.runAsync(() => h.db.select(h.db.features).get());
      expect(rows, hasLength(1));
      final f = rows!.first;
      expect(f.featureType, 'point');
      final geom = jsonDecode(f.geometryGeojson) as Map<String, dynamic>;
      expect(geom['type'], 'Point');
      // Stored as [lng, lat] = [4, 3].
      expect(geom['coordinates'], [4, 3]);
    });

    testWidgets('relocate: second tap replaces vertex; undo stack grows',
        (tester) async {
      final fake = FakeMapRenderer();
      final h = await _pumpSketchHarness(tester, renderer: fake);

      h.container
          .read(geometryEditorControllerProvider.notifier)
          .enterSketch(featureType: 'point');
      await tester.pump();

      await fake.simulateMapTap(1, 1);
      await fake.simulateMapTap(5, 5);
      await tester.pump();

      // Banner still says 1 vertex (point doesn't accumulate).
      expect(find.text('1 vertices · point'), findsOneWidget);

      // Undo enabled: 2 ops on stack (Add then Move).
      final state = h.container.read(geometryEditorControllerProvider);
      expect(state.undoStack.length, 2);

      await tester.tap(find.byKey(const Key('reshape.banner.save')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      final rows = await tester.runAsync(() => h.db.select(h.db.features).get());
      expect(rows, hasLength(1));
      final geom =
          jsonDecode(rows!.first.geometryGeojson) as Map<String, dynamic>;
      // Final coords == (5,5): lng=5, lat=5.
      expect(geom['coordinates'], [5, 5]);
    });
  });

  group('sketch flow — Cancel semantics', () {
    testWidgets('cancel with 0 vertices → no dialog; pill restored',
        (tester) async {
      final fake = FakeMapRenderer();
      final h = await _pumpSketchHarness(tester, renderer: fake);

      await _enterSketchViaPill(tester, 'building');

      // Banner mounted, pill hidden behind sketch banner state.
      expect(find.text('0 vertices · building'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reshape.banner.cancel')));
      await tester.pumpAndSettle();

      // No discard confirm dialog appeared.
      expect(find.text('Discard sketch?'), findsNothing);
      // Banner gone.
      expect(find.text('0 vertices · building'), findsNothing);
      // Sketch state cleared.
      expect(
        h.container.read(geometryEditorControllerProvider).isSketchMode,
        isFalse,
      );
      // +pill back.
      expect(find.byKey(const Key('map.add-feature-pill')), findsOneWidget);
    });

    testWidgets('cancel with ≥1 vertex → confirm dialog; Keep editing retains',
        (tester) async {
      final fake = FakeMapRenderer();
      final h = await _pumpSketchHarness(tester, renderer: fake);

      await _enterSketchViaPill(tester, 'building');
      await fake.simulateMapTap(1, 1);
      await tester.pump();
      expect(find.text('1 vertices · building'), findsOneWidget);

      await tester.tap(find.byKey(const Key('reshape.banner.cancel')));
      await tester.pumpAndSettle();

      // Confirm dialog visible.
      expect(find.text('Discard sketch?'), findsOneWidget);

      // Keep editing → dismissed, vertex retained.
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Discard sketch?'), findsNothing);
      expect(find.text('1 vertices · building'), findsOneWidget);
      expect(
        h.container.read(geometryEditorControllerProvider).isSketchMode,
        isTrue,
      );

      // Cancel again → Discard → state cleared.
      await tester.tap(find.byKey(const Key('reshape.banner.cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Discard sketch?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(
        h.container.read(geometryEditorControllerProvider).isSketchMode,
        isFalse,
      );
      expect(find.byKey(const Key('map.add-feature-pill')), findsOneWidget);
    });
  });

  group('sketch flow — Gesture suppression on existing features', () {
    testWidgets('tapping an existing feature in sketch mode does not navigate',
        (tester) async {
      final existing = Feature(
        id: 'existing-1',
        assignmentId: 'a1',
        featureType: 'building',
        geometryGeojson: '{"type":"Polygon","coordinates":[[[1,1],[2,1],'
            '[2,2],[1,2],[1,1]]]}',
        isNew: false,
        status: 'unfilled',
        createdAt: DateTime.utc(2026),
      );
      final fake = FakeMapRenderer();
      await _pumpSketchHarness(
        tester,
        renderer: fake,
        features: [existing],
      );

      await _enterSketchViaPill(tester, 'building');

      // Tap the existing feature tile. In sketch mode, FakeMapRenderer wires
      // onTap=null, so no navigation should occur.
      // We assert by tapping the feature gesture detector and checking that
      // the feature-detail sentinel never appears.
      await tester.tap(
        find.byKey(const Key('fake-map-feature-existing-1')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('feature-detail-sentinel')), findsNothing);
      // Still in sketch mode — banner present.
      expect(find.text('0 vertices · building'), findsOneWidget);
    });
  });
}
