import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:drift/native.dart';
import 'package:go_router/go_router.dart';
import 'package:firecheck/features/assignment/domain/get_maps_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/assignment/presentation/get_maps_screen.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildSubject(GetMapsState state) {
    return ProviderScope(
      overrides: [
        getMapsNotifierProvider.overrideWith(
          (ref) => _StaticNotifier(state),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GetMapsScreen(),
      ),
    );
  }

  testWidgets('downloading never rounds unverified bytes to 100 percent',
      (tester) async {
    await tester.pumpWidget(
      buildSubject(
        const DownloadingShapefiles(downloaded: 999, total: 1000),
      ),
    );
    await tester.pump();
    expect(find.text('99%'), findsOneWidget);
    expect(find.text('100%'), findsNothing);
  });

  testWidgets('Idle state shows Start download button', (tester) async {
    await tester.pumpWidget(buildSubject(const Idle()));
    await tester.pump();
    expect(find.text('Start download'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('saved map with a different export opens without downloading',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() => tester.runAsync(db.close));
    final repo = AssignmentRepository(db: db, userId: 'me');
    await tester.runAsync(
        () => db.into(db.assignments).insert(AssignmentsCompanion.insert(
              id: 'saved',
              enumeratorId: 'me',
              campaignId: 'c',
              boundaryPolygonGeojson: '',
              createdAt: DateTime(2026),
            )));
    final notifier = _StaticNotifier(PickingAssignment(assignments: const [
      DriveAssignment(
          assignmentId: 'saved',
          localAssignmentId: 'saved',
          inputZipModifiedTime: 'new-export',
          driveFolderId: '',
          downloadedAssignmentId: 'saved'),
      DriveAssignment(
          assignmentId: 'missing',
          localAssignmentId: 'missing',
          inputZipModifiedTime: 'new-export',
          driveFolderId: ''),
    ], selectedId: 'saved'));
    final router = GoRouter(initialLocation: '/get-maps', routes: [
      GoRoute(path: '/get-maps', builder: (_, __) => const GetMapsScreen()),
      GoRoute(
          path: '/map',
          builder: (_, __) => const Scaffold(body: Text('Opened map'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          getMapsNotifierProvider.overrideWith((ref) => notifier),
          assignmentRepositoryProvider.overrideWithValue(repo),
          currentAssignmentProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        )));
    await tester.pumpAndSettle();
    expect(find.text('Downloaded'), findsOneWidget);
    expect(find.text('Not downloaded'), findsOneWidget);
    expect(find.text('Download Selected'), findsNothing);
    await tester.tap(find.text('Work on this map'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('Opened map'), findsOneWidget);
    expect((await tester.runAsync(repo.getCurrentAssignment))?.id, 'saved');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('DownloadingTiles shows progress + Cancel', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        const DownloadingTiles(
          downloadedBytes: 5000000,
          totalBytes: 10000000,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Downloading map tiles…'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.textContaining('MB'), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('Ready state offers explicit selection or My Maps',
      (tester) async {
    await tester.pumpWidget(
      buildSubject(const Ready(featureCount: 10, totalBytes: 1000)),
    );
    await tester.pump();
    expect(find.text('Ready to gather data'), findsOneWidget);
    expect(find.text('Work on this map'), findsOneWidget);
    expect(find.text('Back to My Maps'), findsOneWidget);
  });

  testWidgets('GetMapsError shows retry affordance', (tester) async {
    await tester.pumpWidget(
      buildSubject(
          const GetMapsError(NetworkFailure('no net'), isRetryable: true)),
    );
    await tester.pump();
    expect(find.textContaining('failed'), findsWidgets);
    expect(find.text('Try again'), findsOneWidget);
  });
}

class _StaticNotifier extends StateNotifier<GetMapsState>
    implements GetMapsNotifier {
  _StaticNotifier(super.state);

  @override
  Future<void> start() async {}
  @override
  Future<void> cancel() async {}
  @override
  void reset() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
