import 'package:drift/native.dart';
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

void main() {
  Widget subject() {
    return ProviderScope(
      overrides: [
        mapRendererProvider.overrideWithValue(FakeMapRenderer()),
        currentFeaturesProvider.overrideWith((ref) => Stream.value(const [])),
        currentAssignmentProvider.overrideWith((ref) => Stream.value(null)),
        assignmentLockStateProvider
            .overrideWith((_) => Stream.value(const Unlocked())),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MapScreen(),
      ),
    );
  }

  testWidgets('+ New Feature pill toggles add-mode visual state',
      (tester) async {
    await tester.pumpWidget(subject());
    await tester.pump();

    const banner =
        'Long-press the map to add a building or road. Tap the pill again to cancel.';

    expect(find.text(banner), findsNothing);
    expect(find.text('add-mode'), findsNothing);

    await tester.tap(find.byKey(const Key('map.add-feature-pill')));
    await tester.pump();

    expect(find.text(banner), findsOneWidget);
    expect(find.text('add-mode'), findsOneWidget);

    await tester.tap(find.byKey(const Key('map.add-feature-pill')));
    await tester.pump();

    expect(find.text(banner), findsNothing);
    expect(find.text('add-mode'), findsNothing);
  });

  testWidgets('long-press inside boundary creates feature + routes',
      (tester) async {
    // Create DB inside the test body (FakeAsync zone) per the deadlock note.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final renderer = FakeMapRenderer();
    const boundary =
        '{"type":"Polygon","coordinates":[[[123.88200,10.31720],[123.88340,10.31720],[123.88340,10.31900],[123.88200,10.31900],[123.88200,10.31720]]]}';

    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'admin',
            campaignId: 'c1',
            boundaryPolygonGeojson: boundary,
            createdAt: DateTime.now(),
          ),
        );

    final assignment = Assignment(
      id: 'a1',
      enumeratorId: 'admin',
      campaignId: 'c1',
      boundaryPolygonGeojson: boundary,
      status: 'assigned',
      closedRemotely: false,
      createdAt: DateTime.now(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          mapRendererProvider.overrideWithValue(renderer),
          currentFeaturesProvider.overrideWith((ref) => Stream.value(const [])),
          currentAssignmentProvider
              .overrideWith((ref) => Stream.value(assignment)),
          assignmentLockStateProvider
              .overrideWith((_) => Stream.value(const Unlocked())),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/map',
            routes: [
              GoRoute(path: '/map', builder: (_, __) => const MapScreen()),
              GoRoute(
                path: '/feature/:featureId',
                builder: (_, state) => Scaffold(
                  key: const Key('detail-screen'),
                  appBar: AppBar(
                    title: Text('detail-${state.pathParameters['featureId']}'),
                  ),
                ),
              ),
            ],
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pump();

    // Enter add mode.
    await tester.tap(find.byKey(const Key('map.add-feature-pill')));
    await tester.pump();

    // Simulate long-press at a point inside the boundary.
    await renderer.simulateLongPress(10.31810, 123.88270);
    await tester.pumpAndSettle();

    // Type picker is open; tap Building.
    await tester.tap(find.byKey(const Key('feature-type-picker.building')));
    await tester.pumpAndSettle();

    // Routed to the detail screen.
    expect(find.byKey(const Key('detail-screen')), findsOneWidget);

    // The feature row exists in the DB with isNew=true.
    final features = await db.select(db.features).get();
    expect(features, hasLength(1));
    expect(features.first.isNew, isTrue);
    expect(features.first.featureType, 'building');

    await db.close();
  });
}
