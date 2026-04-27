import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/home/domain/progress_snapshot.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/home/presentation/home_screen.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildSubject(Stream<ProgressSnapshot> stream) {
    return ProviderScope(
      overrides: [
        progressProvider.overrideWith((ref) => stream),
        assignmentLockStateProvider.overrideWith(
          (ref) => Stream.value(const Unlocked()),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomeScreen(),
      ),
    );
  }

  testWidgets('renders empty progress snapshot', (tester) async {
    await tester.pumpWidget(buildSubject(Stream.value(ProgressSnapshot.empty)));
    await tester.pumpAndSettle();

    expect(find.text('0 of 0 features'), findsOneWidget);
    expect(find.text('0 queued · 0 failed · 0 dead'), findsOneWidget);
  });

  testWidgets('renders action tiles for Gather / Get / Upload', (tester) async {
    await tester.pumpWidget(buildSubject(Stream.value(ProgressSnapshot.empty)));
    await tester.pumpAndSettle();

    expect(find.text('Gather Data'), findsOneWidget);
    expect(find.text('Get Maps'), findsOneWidget);
    expect(find.text('Upload Data'), findsOneWidget);
  });

  testWidgets('renders populated progress counts', (tester) async {
    const snap = ProgressSnapshot(
      totalFeatures: 100,
      completedFeatures: 42,
      inProgressFeatures: 5,
      queuedJobs: 3,
      failedJobs: 1,
      deadJobs: 0,
    );
    await tester.pumpWidget(buildSubject(Stream.value(snap)));
    await tester.pumpAndSettle();

    expect(find.text('42 of 100 features'), findsOneWidget);
    expect(find.text('3 queued · 1 failed · 0 dead'), findsOneWidget);
  });
}
