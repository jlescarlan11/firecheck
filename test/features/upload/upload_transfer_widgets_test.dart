import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/upload_transfer_progress.dart';
import 'package:firecheck/features/upload/presentation/upload_transfer_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DriveUploadJob job(String id, String assignment) => DriveUploadJob(
      id: id,
      assignmentId: assignment,
      filePath: '/tmp/$id',
      fileType: 'shapefile',
      fileName: '$id.shp',
      fileSizeBytes: 100,
      capturedAt: DateTime(2026),
      createdAt: DateTime(2026),
      status: 'uploading',
      retryCount: 0,
    );

void main() {
  testWidgets('animates between real targets without advancing during a stall',
      (tester) async {
    final tracker = UploadTransferTracker();
    final file = job('buildings', 'map');
    tracker.update(file, 0, TransferPhase.uploading);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        uploadTransferProgressProvider.overrideWith((ref) => tracker)
      ],
      child: const MaterialApp(
          home:
              Scaffold(body: AssignmentTransferProgress(assignmentId: 'map'))),
    ));
    tracker.update(file, 50, TransferPhase.uploading);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 175));
    final bar = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, greaterThan(0));
    expect(bar.value, lessThan(0.5));
    await tester.pumpAndSettle();
    expect(find.text('50%'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('shows individual percentages for this map and confirms at 100%',
      (tester) async {
    final tracker = UploadTransferTracker();
    final first = job('buildings', 'map');
    tracker.update(first, 42, TransferPhase.uploading);
    tracker.update(job('roads', 'map'), 75, TransferPhase.uploading);
    tracker.update(
        job('private-other-map', 'other'), 10, TransferPhase.uploading);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        uploadTransferProgressProvider.overrideWith((ref) => tracker)
      ],
      child: const MaterialApp(
          home: Scaffold(
        body: AssignmentTransferProgress(assignmentId: 'map'),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('private-other-map.shp'), findsNothing);
    tracker.update(first, 100, TransferPhase.confirming);
    await tester.pumpAndSettle();
    expect(find.text('99% · Confirming…'), findsOneWidget);
    expect(find.text('100% · Uploaded'), findsNothing);
    tracker.update(first, 100, TransferPhase.completed);
    await tester.pumpAndSettle();
    expect(find.text('100% · Uploaded'), findsOneWidget);
  });
}
