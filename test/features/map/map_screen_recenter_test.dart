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
