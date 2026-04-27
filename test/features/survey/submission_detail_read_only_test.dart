import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/building_form/presentation/submission_detail_screen.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hides Done button when assignment is Submitted',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    // Do NOT use addTearDown(db.close) here — we close manually before
    // the widget tree is disposed so that Drift's internal stream-close
    // timer (Timer.run) fires before the test framework's pending-timer
    // invariant check.  (Drift's own comment in stream_queries.dart
    // recommends exactly this pattern for widget tests.)

    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
          id: 'a-1',
          enumeratorId: 'e-1',
          campaignId: 'c-1',
          boundaryPolygonGeojson: '{}',
          createdAt: DateTime(2026, 4, 27),
          submittedAt: Value(DateTime(2026, 4, 27)),
        ),);
    // Use road type so RoadForm (not BuildingForm) mounts.
    // RoadFormNotifier captures state upfront in _flush() before any await,
    // so dispose-time best-effort flushes never access state after
    // super.dispose() and do not produce "used after dispose" test errors.
    await db.into(db.features).insert(FeaturesCompanion.insert(
          id: 'f-1',
          assignmentId: 'a-1',
          featureType: 'road',
          geometryGeojson: '{}',
          createdAt: DateTime(2026, 4, 27),
        ),);
    await db.into(db.submissions).insert(SubmissionsCompanion.insert(
          id: 's-1',
          featureId: 'f-1',
          submittedBy: const Value('u-1'),
          syncStatus: const Value('uploaded'),
          createdAt: DateTime(2026, 4, 27),
          updatedAt: DateTime(2026, 4, 27),
        ),);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          currentUserIdProvider.overrideWithValue('e-1'),
          assignmentLockStateProvider.overrideWith(
            (_) => Stream.value(Submitted(submittedAt: DateTime(2026, 4, 27))),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SubmissionDetailScreen(featureId: 'f-1'),
        ),
      ),
    );
    // Allow the async providers (feature query, submissions stream, lock
    // state) to resolve in real async time.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Done'), findsNothing);

    // Close DB and replace widget tree before the test framework validates
    // pending timers.  This lets Drift's Timer.run() stream-close callbacks
    // fire during the subsequent pump(), clearing them before disposal.
    await db.close();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(Duration.zero);
  });
}
