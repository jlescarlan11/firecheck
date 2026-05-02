import 'package:drift/native.dart';
import 'package:firecheck/core/analytics/analytics_providers.dart';
import 'package:firecheck/core/analytics/analytics_service.dart';
import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/location/location_providers.dart';
import 'package:firecheck/core/location/location_service.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/map/presentation/map_providers.dart';
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:firecheck/features/map/presentation/map_screen.dart';
import 'package:firecheck/features/map/reshape/presentation/reshape_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

Position fakePos({
  required double lat,
  required double lng,
  double accuracy = 10,
}) {
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: DateTime.utc(2026),
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

Feature fakeFeature() => Feature(
      id: 'f1',
      assignmentId: 'a1',
      featureType: 'building',
      geometryGeojson:
          '{"type":"Polygon","coordinates":[[[123.8825,10.3175],'
          '[123.8835,10.3175],[123.8835,10.3185],'
          '[123.8825,10.3185],[123.8825,10.3175]]]}',
      isNew: false,
      status: 'unfilled',
      createdAt: DateTime.utc(2026),
    );

Future<ProviderContainer> pumpMap(
  WidgetTester tester, {
  required FakeMapRenderer renderer,
  List<Feature> features = const [],
  AnalyticsService? analytics,
  Stream<Position>? positionStream,
  AppDatabase? db,
  ValueNotifier<bool>? lockNotifier,
}) async {
  final container = ProviderContainer(
    overrides: [
      mapRendererProvider.overrideWithValue(renderer),
      locationServiceProvider.overrideWithValue(FakeLocationService()),
      // Avoid the Supabase-dependent auth chain in widget tests.
      currentUserIdProvider.overrideWithValue('admin'),
      if (analytics != null)
        analyticsServiceProvider.overrideWithValue(analytics),
      if (db != null) appDatabaseProvider.overrideWithValue(db),
      currentFeaturesProvider.overrideWith((_) => Stream.value(features)),
      currentAssignmentProvider.overrideWith((_) => Stream.value(fakeAssignment())),
      assignmentLockStateProvider.overrideWith((_) => Stream.value(const Unlocked())),
      // For lock-blocker tests, route the synchronous bool through a
      // mutable ValueNotifier so the test can flip the lock mid-flight.
      if (lockNotifier != null)
        isAssignmentLockedProvider.overrideWith((ref) {
          void listener() => ref.invalidateSelf();
          lockNotifier.addListener(listener);
          ref.onDispose(() => lockNotifier.removeListener(listener));
          return lockNotifier.value;
        }),
      currentPositionProvider.overrideWith(
        (_) => positionStream ?? const Stream<Position>.empty(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MapScreen(),
    ),
  ),);
  await tester.pump();
  await tester.pump();
  return container;
}

void main() {
  group('US-9 T18 polygon long-press → reshape action sheet', () {
    testWidgets('long-press on a polygon (add-mode off) opens action sheet',
        (tester) async {
      final renderer = FakeMapRenderer();
      final feature = fakeFeature();
      await pumpMap(tester, renderer: renderer, features: [feature]);

      await renderer.simulatePolygonLongPress(feature);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('reshape.actionsheet.openForm')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('reshape.actionsheet.reshape')),
        findsOneWidget,
      );
    });

    testWidgets('long-press on a polygon (add-mode on) does NOT open sheet',
        (tester) async {
      final renderer = FakeMapRenderer();
      final feature = fakeFeature();
      await pumpMap(tester, renderer: renderer, features: [feature]);

      // Toggle add-mode pill on.
      await tester.tap(find.byKey(const Key('map.add-feature-pill')));
      await tester.pumpAndSettle();

      await renderer.simulatePolygonLongPress(feature);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('reshape.actionsheet.openForm')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('reshape.actionsheet.reshape')),
        findsNothing,
      );
    });
  });

  group('US-9 T19 distance gate + override-reason → enterReshape', () {
    testWidgets('Reshape with GPS within 50m enters edit mode (no dialog)',
        (tester) async {
      final renderer = FakeMapRenderer();
      final analytics = RecordingAnalyticsService();
      final feature = fakeFeature();
      // GPS fix at (essentially) the feature centroid → distance ≈ 0m.
      final container = await pumpMap(
        tester,
        renderer: renderer,
        features: [feature],
        analytics: analytics,
        positionStream: Stream.value(fakePos(lat: 10.3180, lng: 123.8830)),
      );

      await renderer.simulatePolygonLongPress(feature);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reshape.actionsheet.reshape')));
      await tester.pumpAndSettle();

      // No override dialog appeared.
      expect(find.byKey(const Key('override.reason')), findsNothing);

      // Reshape mode is active and the working feature was seeded.
      final state = container.read(reshapeModeControllerProvider);
      expect(state.isActive, isTrue);
      expect(state.originalFeature?.id, feature.id);
      expect(state.overrideReason, isNull);

      // Analytics recorded entry without override.
      expect(
        analytics.events.any((e) =>
            e.event == 'map.reshape.entered' &&
            e.properties?['override_used'] == false &&
            e.properties?['feature_id'] == feature.id,),
        isTrue,
      );
    });

    testWidgets(
        'Reshape with GPS >50m shows override dialog; confirm enters mode',
        (tester) async {
      final renderer = FakeMapRenderer();
      final analytics = RecordingAnalyticsService();
      final feature = fakeFeature();
      // ~155m south of the feature centroid (1° lat ≈ 111km → 0.0014° ≈ 155m).
      final container = await pumpMap(
        tester,
        renderer: renderer,
        features: [feature],
        analytics: analytics,
        positionStream: Stream.value(fakePos(lat: 10.3166, lng: 123.8830)),
      );

      await renderer.simulatePolygonLongPress(feature);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reshape.actionsheet.reshape')));
      await tester.pumpAndSettle();

      // Override dialog visible.
      expect(find.byKey(const Key('override.reason')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('override.reason')),
        'visible from sidewalk',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Override dialog dismissed.
      expect(find.byKey(const Key('override.reason')), findsNothing);

      // Reshape mode active with override reason captured.
      final state = container.read(reshapeModeControllerProvider);
      expect(state.isActive, isTrue);
      expect(state.originalFeature?.id, feature.id);
      expect(state.overrideReason, 'visible from sidewalk');

      // Analytics recorded entry with override.
      expect(
        analytics.events.any((e) =>
            e.event == 'map.reshape.entered' &&
            e.properties?['override_used'] == true &&
            e.properties?['feature_id'] == feature.id,),
        isTrue,
      );
    });
  });

  group('US-9 T20 mount banner + overlay; hide add-pill', () {
    testWidgets('add-mode pill hidden while reshape active', (tester) async {
      final renderer = FakeMapRenderer();
      final feature = fakeFeature();
      // GPS at the feature centroid → distance ≈ 0m, no override dialog.
      await pumpMap(
        tester,
        renderer: renderer,
        features: [feature],
        positionStream: Stream.value(fakePos(lat: 10.3180, lng: 123.8830)),
      );

      // Pill visible at start.
      expect(find.byKey(const Key('map.add-feature-pill')), findsOneWidget);

      await renderer.simulatePolygonLongPress(feature);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reshape.actionsheet.reshape')));
      await tester.pumpAndSettle();

      // Pill hidden once reshape is active.
      expect(find.byKey(const Key('map.add-feature-pill')), findsNothing);
    });

    testWidgets('Cancel exits reshape and re-shows add pill', (tester) async {
      final renderer = FakeMapRenderer();
      final feature = fakeFeature();
      await pumpMap(
        tester,
        renderer: renderer,
        features: [feature],
        positionStream: Stream.value(fakePos(lat: 10.3180, lng: 123.8830)),
      );

      await renderer.simulatePolygonLongPress(feature);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reshape.actionsheet.reshape')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('reshape.banner.cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('map.add-feature-pill')), findsOneWidget);
    });
  });

  group('US-9 T21 Save flow', () {
    testWidgets('Save with valid edits writes revision + sync_job, exits mode',
        (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      // Persist the feature so saveReshape's UPDATE finds a row.
      // runAsync lets the NativeDatabase background isolate complete its writes
      // outside the fakeAsync zone (avoids pumpAndSettle livelock in full suite).
      final feature = fakeFeature();
      await tester.runAsync(() async {
        await db.into(db.assignments).insert(
              AssignmentsCompanion.insert(
                id: 'a1',
                enumeratorId: 'admin',
                campaignId: 'c1',
                boundaryPolygonGeojson: fakeAssignment().boundaryPolygonGeojson,
                createdAt: DateTime.now(),
              ),
            );
        await db.into(db.features).insert(
              FeaturesCompanion.insert(
                id: feature.id,
                assignmentId: feature.assignmentId,
                featureType: feature.featureType,
                geometryGeojson: feature.geometryGeojson,
                createdAt: feature.createdAt,
              ),
            );
      });

      final fake = FakeMapRenderer();
      final container = await pumpMap(
        tester,
        renderer: fake,
        positionStream: Stream.value(fakePos(lat: 10.3180, lng: 123.8830)),
        features: [feature],
        db: db,
      );

      await fake.simulatePolygonLongPress(feature);
      // NativeDatabase background isolate makes pumpAndSettle hang when other
      // tests have left isolates active. Use explicit frame pumps instead.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('reshape.actionsheet.reshape')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Drive the controller into a dirty state by performing a small valid
      // move directly (avoids dependency on overlay layout):
      container.read(reshapeModeControllerProvider.notifier).moveVertex(
            0,
            0,
            (lng: 123.8826, lat: 10.3176),
          );
      await tester.pump();

      await tester.tap(find.byKey(const Key('reshape.banner.save')));
      // Let the NativeDatabase transaction complete in real time, then pump UI.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Mode is inactive in the controller.
      expect(container.read(reshapeModeControllerProvider).isActive, isFalse);
      // Save exited the mode (banner gone).
      expect(find.byKey(const Key('reshape.banner.save')), findsNothing);

      // Revision + sync_job persisted.
      final revisions = await tester.runAsync(
        () => db.select(db.featureGeometryRevisions).get(),
      );
      expect(revisions, hasLength(1));
      expect(revisions!.first.featureId, feature.id);
      expect(revisions.first.syncStatus, 'ready_to_upload');
      final jobs = await tester.runAsync(
        () => db.select(db.syncJobs).get(),
      );
      expect(jobs, hasLength(1));
      expect(jobs!.first.entityType, 'feature_geometry_update');
      expect(jobs.first.entityId, revisions.first.id);
    });

    testWidgets(
        'Save with self-intersecting polygon shows snackbar; stays in mode',
        (tester) async {
      final fake = FakeMapRenderer();
      final analytics = RecordingAnalyticsService();
      final container = await pumpMap(
        tester,
        renderer: fake,
        positionStream: Stream.value(fakePos(lat: 10.3180, lng: 123.8830)),
        features: [fakeFeature()],
        analytics: analytics,
      );

      await fake.simulatePolygonLongPress(fakeFeature());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reshape.actionsheet.reshape')));
      await tester.pumpAndSettle();

      // Drive into a bowtie by swapping the middle two vertices (indices 1 and 2).
      // Original ring: [SW, SE, NE, NW]. After swap: [SW, NE, SE, NW].
      // Edges SW→NE and SE→NW are the two diagonals of the rectangle and cross
      // at its centre — that is the self-intersection.
      // (Swapping indices 0 and 2 only reverses the winding — no crossing.)
      final n = container.read(reshapeModeControllerProvider.notifier);
      final ring = container.read(reshapeModeControllerProvider).workingRings[0];
      final c1 = ring[1];
      final c2 = ring[2];
      n
        ..moveVertex(0, 1, c2) // vertex 1 (SE) → NE position
        ..moveVertex(0, 2, c1); // vertex 2 (NE) → SE position — diagonals cross
      await tester.pump();

      await tester.tap(find.byKey(const Key('reshape.banner.save')));
      // Validation snackbar — pump a few frames for it to mount.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      // Snackbar visible — exact text uses i18n. Check by ARB-key text.
      expect(find.textContaining('cross'), findsWidgets);
      // Still in reshape mode.
      expect(container.read(reshapeModeControllerProvider).isActive, isTrue);

      // Validation_failed analytics fired with the rule name.
      expect(
        analytics.events.any((e) =>
            e.event == 'map.reshape.validation_failed' &&
            e.properties?['rule'] == 'selfIntersection',),
        isTrue,
      );
    });
  });

  group('US-9 T22 lock-while-reshape blocker', () {
    testWidgets('lock-while-dirty shows non-dismissable dialog; Exit discards',
        (tester) async {
      final lockNotifier = ValueNotifier<bool>(false);
      addTearDown(lockNotifier.dispose);
      final fake = FakeMapRenderer();
      final container = await pumpMap(
        tester,
        renderer: fake,
        positionStream: Stream.value(fakePos(lat: 10.3180, lng: 123.8830)),
        features: [fakeFeature()],
        lockNotifier: lockNotifier,
      );

      await fake.simulatePolygonLongPress(fakeFeature());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reshape.actionsheet.reshape')));
      await tester.pumpAndSettle();

      // Make at least one edit so state.isDirty == true.
      container.read(reshapeModeControllerProvider.notifier).moveVertex(
            0,
            0,
            (lng: 123.8835, lat: 10.3185),
          );
      await tester.pumpAndSettle();

      // Trigger lock mid-reshape.
      lockNotifier.value = true;
      await tester.pumpAndSettle();

      expect(find.textContaining('Assignment was closed'), findsOneWidget);
      // Exit button text comes from l.reshapeLockExit ('Exit').
      await tester.tap(find.text('Exit'));
      await tester.pumpAndSettle();

      // Reshape exited; banner gone.
      expect(find.byKey(const Key('reshape.banner.save')), findsNothing);
      expect(
        container.read(reshapeModeControllerProvider).isActive,
        isFalse,
      );
    });

    testWidgets('lock-while-clean exits silently (no dialog)',
        (tester) async {
      final lockNotifier = ValueNotifier<bool>(false);
      addTearDown(lockNotifier.dispose);
      final fake = FakeMapRenderer();
      final container = await pumpMap(
        tester,
        renderer: fake,
        positionStream: Stream.value(fakePos(lat: 10.3180, lng: 123.8830)),
        features: [fakeFeature()],
        lockNotifier: lockNotifier,
      );

      await fake.simulatePolygonLongPress(fakeFeature());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reshape.actionsheet.reshape')));
      await tester.pumpAndSettle();

      // No edits made — state.isDirty == false.

      // Trigger lock.
      lockNotifier.value = true;
      await tester.pumpAndSettle();

      // No dialog.
      expect(find.textContaining('Assignment was closed'), findsNothing);
      // Reshape exited silently.
      expect(
        container.read(reshapeModeControllerProvider).isActive,
        isFalse,
      );
    });
  });
}
