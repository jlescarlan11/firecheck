import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:firecheck/core/theme/app_theme.dart';
// test/features/upload/upload_queue_screen_test.dart
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_preferences.dart';
import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:firecheck/core/security/secure_storage.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_notifier.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DriveUploadJob _makeJob({
  required String id,
  required String status,
  required String fileName,
}) {
  return DriveUploadJob(
    id: id,
    assignmentId: 'a1',
    filePath: '/p.jpg',
    fileType: DriveFileType.photo,
    fileName: fileName,
    fileSizeBytes: 1024,
    capturedAt: DateTime(2026),
    status: status,
    resumableUri: null,
    driveFileId: null,
    retryCount: 0,
    failureReason: null,
    nextRetryAt: null,
    createdAt: DateTime(2026),
  );
}

List<Override> _overrides(DriveUploadState state) => [
      driveUploadNotifierProvider
          .overrideWith((_) => DriveUploadNotifier.seeded(state)),
      driveUploadPreferencesProvider
          .overrideWithValue(DriveUploadPreferences(InMemorySecureStorage())),
    ];

Widget _wrap(DriveUploadState state) {
  return ProviderScope(
    overrides: _overrides(state),
    child: MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const UploadQueueScreen()),
  );
}

class _PagedNotifier extends DriveUploadNotifier {
  _PagedNotifier()
      : super.seeded(DriveUploadState(
          jobs: List.generate(
              50,
              (i) => _makeJob(
                  id: '$i',
                  status: DriveUploadJobStatus.pending,
                  fileName: 'change-$i.shp')),
          totals: const UploadQueueTotals(
              activeCount: 100,
              pendingCount: 100,
              pendingBytes: 100000,
              uploadingCount: 0,
              failedCount: 0),
        ));
  int loadCalls = 0;
  @override
  Future<void> loadMore() async {
    if (!state.hasMore) return;
    loadCalls++;
    state = state.copyWith(
        jobs: List.generate(
            100,
            (i) => _makeJob(
                id: '$i',
                status: DriveUploadJobStatus.pending,
                fileName: 'change-$i.shp')));
  }
}

void main() {
  testWidgets('scrolling near the last loaded change requests another page',
      (tester) async {
    final notifier = _PagedNotifier();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          driveUploadNotifierProvider.overrideWith((_) => notifier),
          driveUploadPreferencesProvider.overrideWithValue(
              DriveUploadPreferences(InMemorySecureStorage())),
        ],
        child: MaterialApp(
            theme: buildAppTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const UploadQueueScreen())));
    await tester.pumpAndSettle();
    expect(notifier.loadCalls, 0);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(notifier.loadCalls, 1);
    expect(notifier.state.jobs, hasLength(100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed history is hidden and large lists build lazily',
      (tester) async {
    await tester.pumpWidget(_wrap(DriveUploadState(jobs: [
      _makeJob(
          id: 'done',
          status: DriveUploadJobStatus.completed,
          fileName: 'completed.shp'),
      for (var i = 0; i < 1000; i++)
        _makeJob(
            id: '$i',
            status: DriveUploadJobStatus.pending,
            fileName: 'change-$i.shp'),
    ])));
    await tester.pumpAndSettle();
    expect(find.text('completed.shp'), findsNothing);
    expect(find.text('change-0.shp'), findsOneWidget);
    expect(find.text('change-999.shp'), findsNothing);
    expect(find.byType(ListTile).evaluate().length, lessThan(20));
  });

  testWidgets('upload controls fit a narrow phone with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_wrap(DriveUploadState(jobs: [
      _makeJob(
          id: 'j1',
          status: DriveUploadJobStatus.failed,
          fileName: 'long-assignment-name-building-photograph.jpg'),
    ])));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.byTooltip('Retry upload'), 160);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Retry upload').hitTestable(), findsOneWidget);
  });
  testWidgets('shows empty message when no pending files', (tester) async {
    await tester.pumpWidget(_wrap(const DriveUploadState(jobs: [])));

    expect(find.text('No pending uploads'), findsOneWidget);
  });

  testWidgets('shows file rows when jobs exist', (tester) async {
    final state = DriveUploadState(
      jobs: [
        _makeJob(
          id: 'j1',
          status: DriveUploadJobStatus.pending,
          fileName: 'photo1.jpg',
        ),
      ],
    );

    await tester.pumpWidget(_wrap(state));

    expect(find.text('photo1.jpg'), findsOneWidget);
    expect(find.textContaining('Pending'), findsOneWidget);
  });

  testWidgets('Upload All button is present and enabled with pending jobs',
      (tester) async {
    final state = DriveUploadState(
      jobs: [
        _makeJob(
          id: 'j1',
          status: DriveUploadJobStatus.pending,
          fileName: 'photo1.jpg',
        ),
      ],
    );

    await tester.pumpWidget(_wrap(state));

    final btn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Upload All'),
    );
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('Upload All button disabled when uploading', (tester) async {
    final state = DriveUploadState(
      jobs: [
        _makeJob(
          id: 'j1',
          status: DriveUploadJobStatus.uploading,
          fileName: 'photo1.jpg',
        ),
      ],
    );

    await tester.pumpWidget(_wrap(state));

    final btn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Upload All'),
    );
    expect(btn.onPressed, isNull);
  });
}
