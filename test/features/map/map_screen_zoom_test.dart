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
      await renderer.simulateCameraChanged(15, 10.318, 123.883);
      await tester.pump();

      await tester.tap(find.byKey(const Key('map.zoom-in-button')));
      await tester.pump();

      expect(renderer.cameraTargetHistory, isNotEmpty);
      final last = renderer.cameraTargetHistory.last;
      expect(last.zoom, 16);
      expect(last.animation, CameraAnimation.ease);
    });

    testWidgets('AC3: tap zoom-out pushes ease target with zoom − 1',
        (tester) async {
      final renderer = FakeMapRenderer();
      await pumpMap(tester, renderer: renderer);

      await renderer.simulateCameraChanged(15, 10.318, 123.883);
      await tester.pump();

      await tester.tap(find.byKey(const Key('map.zoom-out-button')));
      await tester.pump();

      expect(renderer.cameraTargetHistory, isNotEmpty);
      final last = renderer.cameraTargetHistory.last;
      expect(last.zoom, 14);
      expect(last.animation, CameraAnimation.ease);
    });
  });

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

      await renderer.simulateCameraChanged(22, 10.318, 123.883);
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

      await renderer.simulateCameraChanged(0, 10.318, 123.883);
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
      await renderer.simulateCameraChanged(15, 10.318, 123.883);
      await tester.pump();
      expect(opacityForIcon(tester, Icons.add).opacity, 1.0);

      // User pinches outward; renderer reports max zoom.
      await renderer.simulateCameraChanged(22, 10.318, 123.883);
      await tester.pump();

      expect(opacityForIcon(tester, Icons.add).opacity, 0.5);
    });
  });
}
