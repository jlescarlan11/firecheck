import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/map/presentation/map_providers.dart';
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:firecheck/features/map/presentation/map_screen.dart';
import 'package:firecheck/features/remote_activity/presentation/remote_activity_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildSubject({
    required List<Feature> features,
    Assignment? assignment,
  }) {
    return ProviderScope(
      overrides: [
        mapRendererProvider.overrideWithValue(FakeMapRenderer()),
        currentFeaturesProvider.overrideWith((ref) => Stream.value(features)),
        currentAssignmentProvider
            .overrideWith((ref) => Stream.value(assignment)),
        assignmentLockStateProvider
            .overrideWith((_) => Stream.value(const Unlocked())),
        othersRemoteAttributionsProvider.overrideWith(
          (_) => Stream.value(const []),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MapScreen(),
      ),
    );
  }

  testWidgets('renders title; no Follow-me pill (deleted in US-12)',
      (tester) async {
    await tester.pumpWidget(buildSubject(features: const []));
    await tester.pump();
    expect(find.text('Gather Data'), findsOneWidget);
    expect(find.text('Follow'), findsNothing);
  });

  testWidgets('renders one fake-map tile per feature', (tester) async {
    final f = Feature(
      id: 'f1',
      assignmentId: 'a1',
      featureType: 'building',
      geometryGeojson: '{}',
      isNew: false,
      status: 'unfilled',
      createdAt: DateTime.now(),
    );
    final a = Assignment(
      id: 'a1',
      enumeratorId: 'e1',
      campaignId: 'c1',
      boundaryPolygonGeojson: '{}',
      status: 'assigned',
      closedRemotely: false,
      createdAt: DateTime.now(),
    );
    await tester.pumpWidget(buildSubject(features: [f], assignment: a));
    await tester.pump();
    expect(find.byKey(const Key('fake-map-feature-f1')), findsOneWidget);
  });

  testWidgets('passes a boundary-derived initialCameraTarget to the renderer',
      (tester) async {
    final renderer = FakeMapRenderer();
    final assignment = Assignment(
      id: 'a1',
      enumeratorId: 'e@example.com',
      campaignId: 'c1',
      boundaryPolygonGeojson:
          '{"type":"Polygon","coordinates":[[ '
          '[123.882,10.317],[123.884,10.317],'
          '[123.884,10.319],[123.882,10.319],'
          '[123.882,10.317]]]}',
      status: 'assigned',
      closedRemotely: false,
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        mapRendererProvider.overrideWithValue(renderer),
        currentFeaturesProvider.overrideWith((_) => Stream.value(const [])),
        currentAssignmentProvider.overrideWith((_) => Stream.value(assignment)),
        assignmentLockStateProvider.overrideWith((_) => Stream.value(const Unlocked())),
        othersRemoteAttributionsProvider.overrideWith(
          (_) => Stream.value(const []),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MapScreen(),
      ),
    ),);
    await tester.pump();

    expect(renderer.lastInitialCameraTarget, isNotNull);
    expect(renderer.lastInitialCameraTarget!.lat, closeTo(10.318, 1e-3));
    expect(renderer.lastInitialCameraTarget!.lng, closeTo(123.883, 1e-3));
    expect(
      renderer.lastInitialCameraTarget!.zoom,
      inInclusiveRange(12.0, 18.0),
    );
  });

  testWidgets(
    'FakeMapRenderer.simulateMapTap fires onMapTap with the right coords',
    (tester) async {
      double? gotLat;
      double? gotLng;
      final fake = FakeMapRenderer();
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => fake.build(
            ctx,
            features: const [],
            boundaryGeojson: '',
            onFeatureTap: (_) {},
            sketchActive: true,
            onMapTap: (lat, lng) {
              gotLat = lat;
              gotLng = lng;
            },
          ),
        ),
      ),);
      await fake.simulateMapTap(1.5, 2.5);
      expect(gotLat, 1.5);
      expect(gotLng, 2.5);
    },
  );
}
