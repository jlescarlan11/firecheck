import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/presentation/sections/failed_jobs_section.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('returns SizedBox.shrink when no dead jobs', (tester) async {
    var retryAllCount = 0;
    var retryOneIds = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FailedJobsSection(
            deadJobs: const [],
            onRetryAll: () => retryAllCount++,
            onRetryOne: (id) => retryOneIds.add(id),
          ),
        ),
      ),
    );
    expect(find.textContaining('Failed'), findsNothing);
  });

  testWidgets('renders 1 row + Retry all + per-row Retry', (tester) async {
    var retryAllCount = 0;
    var retryOneIds = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FailedJobsSection(
            deadJobs: const [
              DeadJobRow(
                jobId: 'j-1',
                entityType: 'photo',
                entityId: 'p-1',
                attempts: 5,
                lastError: 'Network',
              ),
            ],
            onRetryAll: () => retryAllCount++,
            onRetryOne: retryOneIds.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Failed'), findsOneWidget);
    expect(find.textContaining('Retry all'), findsOneWidget);

    await tester.tap(find.textContaining('Retry all'));
    expect(retryAllCount, 1);

    await tester.tap(find.byKey(const Key('failedJobs.retry-j-1')));
    expect(retryOneIds, ['j-1']);
  });
}
