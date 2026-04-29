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

Future<void> pumpMap(
  WidgetTester tester, {
  required FakeMapRenderer renderer,
  List<Feature> features = const [],
  AnalyticsService? analytics,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mapRendererProvider.overrideWithValue(renderer),
      locationServiceProvider.overrideWithValue(FakeLocationService()),
      if (analytics != null)
        analyticsServiceProvider.overrideWithValue(analytics),
      currentFeaturesProvider.overrideWith((_) => Stream.value(features)),
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
}
