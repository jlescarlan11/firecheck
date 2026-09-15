import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:firecheck/core/theme/app_theme.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/home/domain/progress_snapshot.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/home/presentation/home_screen.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_notifier.dart';
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
        driveUploadNotifierProvider.overrideWith(
          (_) => DriveUploadNotifier.seeded(const DriveUploadState(jobs: [])),
        ),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomeScreen(),
      ),
    );
  }

  testWidgets('renders empty progress snapshot', (tester) async {
    await tester.pumpWidget(buildSubject(Stream.value(ProgressSnapshot.empty)));
    await tester.pumpAndSettle();

    expect(find.text('0 / 0'), findsOneWidget);
    expect(find.text('0% complete'), findsOneWidget);
  });

  testWidgets('empty workspace disables map and offers downloads',
      (tester) async {
    await tester.pumpWidget(buildSubject(Stream.value(ProgressSnapshot.empty)));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('home-survey-action')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('No maps downloaded'), findsOneWidget);
    expect(find.byTooltip('Uploads'), findsOneWidget);
  });

  testWidgets('home fits a narrow phone with enlarged text', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(buildSubject(Stream.value(ProgressSnapshot.empty)));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byType(SingleChildScrollView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('home error offers retry', (tester) async {
    await tester.pumpWidget(buildSubject(Stream.error(Exception('offline'))));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load your field work."), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('renders survey action and data management rows', (tester) async {
    await tester.pumpWidget(buildSubject(Stream.value(ProgressSnapshot.empty)));
    await tester.pumpAndSettle();

    expect(find.text('Start survey'), findsOneWidget);
    expect(find.text('Get maps'), findsOneWidget);
    expect(find.text('Review & upload'), findsOneWidget);
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

    expect(find.text('42 / 100'), findsOneWidget);
    expect(find.text('1 survey sync needs attention'), findsOneWidget);
    expect(find.text('42% complete'), findsOneWidget);
    expect(find.text('58 remaining'), findsOneWidget);
  });
}
