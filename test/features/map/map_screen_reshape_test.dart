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
}) async {
  final container = ProviderContainer(
    overrides: [
      mapRendererProvider.overrideWithValue(renderer),
      locationServiceProvider.overrideWithValue(FakeLocationService()),
      if (analytics != null)
        analyticsServiceProvider.overrideWithValue(analytics),
      currentFeaturesProvider.overrideWith((_) => Stream.value(features)),
      currentAssignmentProvider.overrideWith((_) => Stream.value(fakeAssignment())),
      assignmentLockStateProvider.overrideWith((_) => Stream.value(const Unlocked())),
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
}
