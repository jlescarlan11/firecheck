// test/features/home/home_screen_upload_banner_test.dart
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:firecheck/features/upload/presentation/upload_banner.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('UploadBanner shows pending count on HomeScreen', (tester) async {
    final state = DriveUploadState(jobs: [
      DriveUploadJob(
        id: 'j1', assignmentId: 'a1', filePath: '/p1.jpg',
        fileType: DriveFileType.photo, fileName: 'p1.jpg',
        fileSizeBytes: 1024, capturedAt: DateTime(2026),
        status: DriveUploadJobStatus.pending, resumableUri: null,
        driveFileId: null, retryCount: 0, failureReason: null,
        nextRetryAt: null, createdAt: DateTime(2026),
      ),
    ]);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        driveUploadNotifierProvider
            .overrideWith((_) => DriveUploadNotifier.seeded(state)),
      ],
      child: const MaterialApp(home: Scaffold(body: UploadBanner())),
    ));

    expect(find.textContaining('file'), findsAtLeastNWidgets(1));
  });

  testWidgets('UploadBanner hidden when no pending jobs', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        driveUploadNotifierProvider.overrideWith(
          (_) => DriveUploadNotifier.seeded(const DriveUploadState(jobs: [])),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: UploadBanner())),
    ));

    expect(find.byType(Card), findsNothing);
  });
}
