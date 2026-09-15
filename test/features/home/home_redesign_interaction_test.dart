import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:firecheck/core/security/biometric_gate.dart';
import 'package:firecheck/core/security/biometric_gate_provider.dart';
import 'package:firecheck/core/sync/shapefile/export/export_validation_result.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_export_validator.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_exporter.dart';
import 'package:firecheck/core/theme/app_theme.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/conflict_review/presentation/conflict_review_providers.dart';
import 'package:firecheck/features/home/data/shapefile_export_notifier.dart';
import 'package:firecheck/features/home/domain/progress_snapshot.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/home/presentation/home_screen.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_notifier.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _Biometric extends Mock implements BiometricGate {}

class _Validator extends Mock implements ShapefileExportValidator {}

class _Exporter extends Mock implements ShapefileExporter {}

const _progress = ProgressSnapshot(
  totalFeatures: 60,
  completedFeatures: 24,
  inProgressFeatures: 2,
  queuedJobs: 0,
  failedJobs: 0,
  deadJobs: 0,
);

DriveUploadJob _job(String status) => DriveUploadJob(
      id: status,
      assignmentId: 'assignment',
      filePath: '/photo.jpg',
      fileType: DriveFileType.photo,
      fileName: 'photo.jpg',
      fileSizeBytes: 1024,
      capturedAt: DateTime(2026, 9, 15),
      status: status,
      retryCount: 0,
      createdAt: DateTime(2026, 9, 15),
    );

void main() {
  late _Biometric biometric;
  late _Validator validator;
  late _Exporter exporter;
  late GoRouter router;

  setUp(() {
    biometric = _Biometric();
    validator = _Validator();
    exporter = _Exporter();
    when(() => biometric.isAvailable()).thenAnswer((_) async => true);
    when(() => biometric.authenticate(reason: any(named: 'reason')))
        .thenAnswer((_) async => true);
    when(() => validator.validate(any()))
        .thenAnswer((_) async => const ExportValidationResult(errors: []));
    when(() => exporter.export(assignmentId: any(named: 'assignmentId')))
        .thenAnswer((_) async => null);
    router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
        for (final path in [
          '/map',
          '/get-maps',
          '/review',
          '/uploads',
          '/account',
          '/resolve',
        ])
          GoRoute(
            path: path,
            builder: (_, __) => Scaffold(body: Text('Destination $path')),
          ),
      ],
    );
  });
  tearDown(() => router.dispose());

  Future<void> pumpHome(
    WidgetTester tester, {
    ProgressSnapshot progress = _progress,
    List<DriveUploadJob> jobs = const [],
    Locale locale = const Locale('en'),
    int conflicts = 0,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          progressProvider.overrideWith((_) => Stream.value(progress)),
          assignmentLockStateProvider
              .overrideWith((_) => Stream.value(const Unlocked())),
          awaitingResolutionCountProvider.overrideWithValue(conflicts),
          driveUploadNotifierProvider.overrideWith(
            (_) => DriveUploadNotifier.seeded(DriveUploadState(jobs: jobs)),
          ),
          biometricGateProvider.overrideWithValue(biometric),
          shapefileExportNotifierProvider.overrideWith(
            (_) => ShapefileExportNotifier(
              assignmentId: 'assignment',
              exporter: exporter,
              validator: validator,
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: buildAppTheme(),
          routerConfig: router,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('survey, downloads, upload queue and account retain navigation',
      (tester) async {
    await pumpHome(tester);
    for (final entry in {
      'Continue survey': '/map',
      'Get maps': '/get-maps',
      'Account': '/account',
    }.entries) {
      await tester.ensureVisible(find.text(entry.key));
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(find.text('Destination ${entry.value}'), findsOneWidget);
      router.go('/');
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('Upload progress'));
    await tester.pumpAndSettle();
    expect(find.text('Destination /uploads'), findsOneWidget);
  });

  testWidgets('review action respects biometric cancellation and success',
      (tester) async {
    when(() => biometric.authenticate(reason: any(named: 'reason')))
        .thenAnswer((_) async => false);
    await pumpHome(tester);
    await tester.ensureVisible(find.text('Review before upload'));
    await tester.tap(find.text('Review before upload'));
    await tester.pumpAndSettle();
    expect(find.text('Destination /review'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    when(() => biometric.authenticate(reason: any(named: 'reason')))
        .thenAnswer((_) async => true);
    await tester.tap(find.text('Review before upload'));
    await tester.pumpAndSettle();
    expect(find.text('Destination /review'), findsOneWidget);
  });

  testWidgets('review remains available on devices without biometrics',
      (tester) async {
    when(() => biometric.isAvailable()).thenAnswer((_) async => false);
    await pumpHome(tester);
    await tester.ensureVisible(find.text('Review before upload'));
    await tester.tap(find.text('Review before upload'));
    await tester.pumpAndSettle();
    expect(find.text('Destination /review'), findsOneWidget);
    verifyNever(() => biometric.authenticate(reason: any(named: 'reason')));
  });

  testWidgets('export menu runs validation and exports completed work',
      (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export Shapefile'));
    await tester.pumpAndSettle();
    verify(() => validator.validate('assignment')).called(1);
    verify(() => exporter.export(assignmentId: 'assignment')).called(1);
  });

  testWidgets('export menu disables export when there is no completed work',
      (tester) async {
    await pumpHome(tester, progress: ProgressSnapshot.empty);
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
          .enabled,
      isFalse,
    );
    verifyNever(() => validator.validate(any()));
  });

  testWidgets('queue badge excludes completed files and exposes failed files',
      (tester) async {
    await pumpHome(
      tester,
      jobs: [
        _job(DriveUploadJobStatus.completed),
        _job(DriveUploadJobStatus.pending),
        _job(DriveUploadJobStatus.uploading),
        _job(DriveUploadJobStatus.failed),
      ],
    );
    expect(find.text('1 file needs a retry'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Badge), matching: find.text('3')),
      findsOneWidget,
    );
    expect(find.textContaining('Working offline'), findsNothing);
  });

  testWidgets('Tagalog and enlarged text fit and keep actions reachable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpHome(tester, locale: const Locale('tl'));
    await tester.ensureVisible(find.text('Suriin bago i-upload'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Suriin bago i-upload'));
    await tester.pumpAndSettle();
    expect(find.text('Destination /review'), findsOneWidget);
  });

  testWidgets('conflict notice remains actionable', (tester) async {
    await pumpHome(tester, conflicts: 1);
    await tester.tap(find.byKey(const Key('conflict-banner')));
    await tester.pumpAndSettle();
    expect(find.text('Destination /resolve'), findsOneWidget);
  });
}
