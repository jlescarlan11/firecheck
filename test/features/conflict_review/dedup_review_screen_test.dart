import 'dart:async';

import 'package:drift/native.dart';
import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/geo/comparison_geometry.dart';
import 'package:firecheck/core/sync/domain/resolution_decision.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/conflict_review/data/conflict_review_repository.dart';
import 'package:firecheck/features/conflict_review/data/dedup_comparison_repository.dart';
import 'package:firecheck/features/conflict_review/domain/dedup_comparison.dart';
import 'package:firecheck/features/conflict_review/presentation/conflict_review_providers.dart';
import 'package:firecheck/features/conflict_review/presentation/dedup_review_screen.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'dedup_test_fixture.dart';

class PendingRepository extends ConflictReviewRepository {
  PendingRepository(super.db);
  Completer<void> completion = Completer<void>();
  int calls = 0;
  @override
  Future<void> queueDedupDecision({
    required String featureId,
    required DedupDecision decision,
    String? resolutionNote,
  }) {
    calls++;
    return completion.future;
  }
}

class QueueComparisonRepository extends DedupComparisonRepository {
  QueueComparisonRepository(super.db);
  @override
  Future<void> queueDecision({
    required DedupComparison comparison,
    required DedupDecision decision,
    required ConflictReviewRepository resolutions,
    bool Function()? isCurrentContext,
  }) =>
      resolutions.queueDedupDecision(
        featureId: comparison.mine.id,
        decision: decision,
      );
}

void main() {
  testWidgets(
      'missing comparison explains unavailable and keeps Skip available',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(280, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const DedupReviewScreen(featureId: 'missing'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue(null),
          currentAssignmentProvider.overrideWith((_) => Stream.value(null)),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Comparison unavailable'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('dedup-review.keep-both')),
          )
          .onPressed,
      isNull,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('dedup-review.skip')),
      200,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('dedup-review.skip')))
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });
  testWidgets(
      'loading, lookup error and explicit retry keep decisions disabled',
      (tester) async {
    var attempts = 0;
    final loading = StreamController<DedupComparison?>();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const DedupReviewScreen(featureId: 'mine'),
        ),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(400, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue(null),
          currentAssignmentProvider.overrideWith((_) => Stream.value(null)),
          dedupComparisonProvider('mine').overrideWith(
            (_) => ++attempts == 1 ? loading.stream : Stream.value(null),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    loading.addError(StateError('cache unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Comparison unavailable'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('dedup-review.keep-both')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Retry comparison'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Comparison unavailable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    unawaited(loading.close());
  });
  for (final failFirst in [false, true]) {
    testWidgets('decision busy, selection and retry flow (failure: $failFirst)',
        (tester) async {
      final db = (await tester.runAsync(
        () async => AppDatabase.forTesting(NativeDatabase.memory()),
      ))!;
      await tester.binding.setSurfaceSize(const Size(280, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final assignment = Assignment(
        id: 'a',
        enumeratorId: 'u',
        campaignId: 'c',
        boundaryPolygonGeojson: polygon,
        status: 'assigned',
        closedRemotely: false,
        createdAt: DateTime.utc(2026),
      );
      final geometry = ComparisonGeometry.parse(polygon)!;
      final comparison = DedupComparison(
        assignmentId: 'a',
        accountId: 'u',
        mine: ComparedFeature(
          id: 'mine',
          featureType: 'building',
          geometry: geometry,
        ),
        existing: ComparedFeature(
          id: 'existing',
          featureType: 'building',
          geometry: geometry,
        ),
      );
      final repo = PendingRepository(db);
      final selection = StreamController<Assignment?>()..add(assignment);
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, __) => const Text('Returned')),
          GoRoute(
            path: '/review',
            builder: (_, __) => const DedupReviewScreen(featureId: 'mine'),
          ),
        ],
      );
      // Push so successful resolution has a destination to return to.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dedupComparisonProvider('mine')
                .overrideWith((_) => Stream.value(comparison)),
            appDatabaseProvider.overrideWithValue(db),
            dedupComparisonRepositoryProvider
                .overrideWithValue(QueueComparisonRepository(db)),
            currentUserIdProvider.overrideWithValue('u'),
            currentAssignmentProvider.overrideWith((_) => selection.stream),
            conflictReviewRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(router.push<void>('/review'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dedup-review.geometry')), findsOneWidget);
      expect(
        find.textContaining('Mine — solid line, round markers: mine'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Existing feature — square markers: existing'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      selection.add(null);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dedup-review.geometry')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('dedup-review.keep-both')),
            )
            .onPressed,
        isNull,
      );
      selection.add(assignment);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dedup-review.keep-both')));
      await tester.pump();
      expect(repo.calls, 1);
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('dedup-review.keep-both')),
            )
            .onPressed,
        isNull,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('dedup-review.skip')),
        200,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('dedup-review.skip')))
            .onPressed,
        isNull,
      );
      if (failFirst) {
        repo.completion.completeError(StateError('disk full'));
        await tester.pumpAndSettle();
        expect(
          find.text('Could not save your decision. Please try again.'),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.byKey(const Key('dedup-review.keep-both')),
          -200,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('dedup-review.keep-both')),
              )
              .onPressed,
          isNotNull,
        );
        repo.completion = Completer<void>();
        await tester.tap(find.byKey(const Key('dedup-review.keep-both')));
        await tester.pump();
        expect(repo.calls, 2);
      }
      repo.completion.complete();
      await tester.pumpAndSettle();
      expect(find.text('Returned'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      unawaited(selection.close());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(db.close);
    });
  }
}
