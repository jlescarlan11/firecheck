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
    child: const MaterialApp(home: UploadQueueScreen()),
  );
}

void main() {
  testWidgets('shows empty message when no pending files', (tester) async {
    await tester.pumpWidget(_wrap(const DriveUploadState(jobs: [])));

    expect(find.text('No pending uploads'), findsOneWidget);
  });

  testWidgets('shows file rows when jobs exist', (tester) async {
    final state = DriveUploadState(jobs: [
      _makeJob(
        id: 'j1',
        status: DriveUploadJobStatus.pending,
        fileName: 'photo1.jpg',
      ),
    ]);

    await tester.pumpWidget(_wrap(state));

    expect(find.text('photo1.jpg'), findsOneWidget);
    expect(find.textContaining('PENDING'), findsOneWidget);
  });

  testWidgets('Upload All button is present and enabled with pending jobs',
      (tester) async {
    final state = DriveUploadState(jobs: [
      _makeJob(
        id: 'j1',
        status: DriveUploadJobStatus.pending,
        fileName: 'photo1.jpg',
      ),
    ]);

    await tester.pumpWidget(_wrap(state));

    final btn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Upload All'),
    );
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('Upload All button disabled when uploading', (tester) async {
    final state = DriveUploadState(jobs: [
      _makeJob(
        id: 'j1',
        status: DriveUploadJobStatus.uploading,
        fileName: 'photo1.jpg',
      ),
    ]);

    await tester.pumpWidget(_wrap(state));

    final btn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Upload All'),
    );
    expect(btn.onPressed, isNull);
  });
}
