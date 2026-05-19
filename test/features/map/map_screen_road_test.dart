import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/location/location_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/map/presentation/map_providers.dart';
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:firecheck/features/map/presentation/map_screen.dart';
import 'package:firecheck/features/remote_activity/presentation/remote_activity_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:go_router/go_router.dart';

const _kRoadGeojson =
    '{"type":"LineString","coordinates":[[120.0,14.0],[121.0,14.5]]}';

Feature _roadFeature({String status = 'not_started'}) => Feature(
      id: 'r1',
      assignmentId: 'a1',
      featureType: 'road',
      geometryGeojson: _kRoadGeojson,
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
      // Map-badge chip — short-circuit its Drift watch so pending timers
      // don't leak across the test boundary.
      othersRemoteAttributionsProvider.overrideWith(
        (_) => Stream.value(const []),
      ),
      // Emit a position exactly at the road midpoint so _resolvePosition
      // returns immediately (distance = 0 m → no override dialog, no
      // CircularProgressIndicator, no infinite animation for pumpAndSettle).
      currentPositionProvider.overrideWith((_) => Stream.value(Position(
            latitude: 14.25,
            longitude: 120.5,
            timestamp: DateTime.utc(2026),
            accuracy: 1,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          ))),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

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

    expect(find.byKey(const Key('fake-map-feature-r1')), findsOneWidget,);
    expect(find.byKey(const Key('fake-map-poly-r1')), findsOneWidget,);
  });

  testWidgets('tapping road tile navigates to /feature/r1', (tester) async {
    final now = DateTime.now();
    await tester.runAsync(() async {
      await db.into(db.features).insert(FeaturesCompanion.insert(
            id: 'r1',
            assignmentId: 'a1',
            featureType: 'road',
            geometryGeojson: _kRoadGeojson,
            status: const Value('not_started'), // required for ensureDraftForFeature upsert
            createdAt: now,
          ));
    });

    await tester.pumpWidget(_buildSubject(
      featuresStream: Stream.value([_roadFeature()]),
      db: db,
    ));
    // Multiple pumps ensure Riverpod's StreamProvider has transitioned to
    // AsyncData(pos) so _resolvePosition returns the cached position
    // immediately (no GPS dialog, no 8-second timeout timer in fake-async).
    await tester.pump();
    await tester.pump();
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('fake-map-feature-r1')));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pump();
    });
    await tester.pump(const Duration(milliseconds: 500));

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
