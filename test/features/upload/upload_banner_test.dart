// test/features/upload/upload_banner_test.dart
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:firecheck/features/upload/presentation/upload_banner.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, DriveUploadState state) {
  return ProviderScope(
    overrides: [
      driveUploadNotifierProvider
          .overrideWith((_) => DriveUploadNotifier.seeded(state)),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

DriveUploadJob _makeJob({
  required String id,
  required String status,
  required int sizeBytes,
}) {
  return DriveUploadJob(
    id: id,
    assignmentId: 'a1',
    filePath: '/p.jpg',
    fileType: 'photo',
    fileName: 'p.jpg',
    fileSizeBytes: sizeBytes,
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

void main() {
  testWidgets('banner is hidden when no pending jobs', (tester) async {
    await tester.pumpWidget(
      _wrap(const UploadBanner(), const DriveUploadState(jobs: [])),
    );

    expect(find.byType(Card), findsNothing);
    expect(find.textContaining('file'), findsNothing);
  });

  testWidgets('banner shows singular label for one pending job', (tester) async {
    final state = DriveUploadState(jobs: [
      _makeJob(id: 'j1', status: 'pending', sizeBytes: 1024 * 1024),
    ]);

    await tester.pumpWidget(_wrap(const UploadBanner(), state));

    expect(find.text('1 file ready to upload'), findsOneWidget);
    expect(find.text('1.0 MB'), findsOneWidget);
  });

  testWidgets('banner shows plural label for multiple pending jobs',
      (tester) async {
    final state = DriveUploadState(jobs: [
      _makeJob(id: 'j1', status: 'pending', sizeBytes: 1024 * 1024),
      _makeJob(id: 'j2', status: 'failed', sizeBytes: 2 * 1024 * 1024),
    ]);

    await tester.pumpWidget(_wrap(const UploadBanner(), state));

    expect(find.text('2 files ready to upload'), findsOneWidget);
    expect(find.text('3.0 MB'), findsOneWidget);
  });

  testWidgets('banner excludes uploading jobs from pending count',
      (tester) async {
    final state = DriveUploadState(jobs: [
      _makeJob(id: 'j1', status: 'pending', sizeBytes: 1024 * 1024),
      _makeJob(id: 'j2', status: 'uploading', sizeBytes: 5 * 1024 * 1024),
    ]);

    await tester.pumpWidget(_wrap(const UploadBanner(), state));

    expect(find.text('1 file ready to upload'), findsOneWidget);
  });
}
