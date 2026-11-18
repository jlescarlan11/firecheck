import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/assignment/presentation/my_maps_screen.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('lists both maps and explicitly selects the tapped map',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    await tester.runAsync(() async {
      for (final name in ['Cebu', 'Guadalupe']) {
        await db.into(db.assignments).insert(AssignmentsCompanion.insert(
              id: name,
              name: Value(name),
              enumeratorId: 'me',
              campaignId: name,
              boundaryPolygonGeojson: '',
              createdAt: DateTime.now(),
            ));
      }
    });
    final maps = await tester.runAsync(() => db.select(db.assignments).get());
    final container = ProviderContainer(overrides: [
      downloadedAssignmentsProvider.overrideWith((_) => Stream.value(maps!)),
      currentAssignmentProvider.overrideWith((_) => Stream.value(null)),
      mapSummaryProvider.overrideWith((_, id) => Stream.value('0/0 gathered')),
      appDatabaseProvider.overrideWithValue(db),
      currentUserIdProvider.overrideWithValue('me'),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/my-maps', routes: [
      GoRoute(path: '/my-maps', builder: (_, __) => const MyMapsScreen()),
      GoRoute(
          path: '/map',
          builder: (_, __) => const Scaffold(body: Text('Gathering map'))),
      GoRoute(
          path: '/get-maps',
          builder: (_, __) => const Scaffold(body: Text('Download maps'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp.router(routerConfig: router)));

    await tester.pumpAndSettle();
    expect(find.text('Cebu'), findsOneWidget);
    expect(find.text('Guadalupe'), findsOneWidget);
    expect(
        await tester.runAsync(() => container
            .read(assignmentRepositoryProvider)
            .getCurrentAssignment()),
        isNull);
    await tester.tap(find.text('Cebu'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('Gathering map'), findsOneWidget);
    final selected = await tester.runAsync(() =>
        container.read(assignmentRepositoryProvider).getCurrentAssignment());
    expect(selected?.id, 'Cebu');
  });
}
