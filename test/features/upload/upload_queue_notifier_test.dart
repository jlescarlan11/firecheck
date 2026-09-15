import 'package:drift/drift.dart' show Value;
// test/features/upload/upload_queue_notifier_test.dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:firecheck/core/drive/fake_drive_upload_api.dart';
import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pages outstanding rows while totals include unseen changes', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime(2026);
    await db.batch((batch) => batch.insertAll(db.driveUploadJobs, [
          for (var i = 0; i < 603; i++)
            DriveUploadJobsCompanion.insert(
                id: 'j${i.toString().padLeft(4, '0')}',
                assignmentId: 'a1',
                filePath: '/$i.shp',
                fileName: '$i.shp',
                fileType: DriveFileType.shapefile,
                fileSizeBytes: 100,
                capturedAt: now,
                createdAt: now,
                status: Value(i >= 103
                    ? DriveUploadJobStatus.completed
                    : DriveUploadJobStatus.pending)),
        ]));
    final repo = DriveUploadRepository(db);
    await repo.markUploading('j0102');
    await repo.markDead('j0101', reason: 'Retry needed');
    final container = ProviderContainer(overrides: [
      driveUploadRepoProvider.overrideWithValue(repo),
      driveUploadWorkerProvider.overrideWithValue(DriveUploadWorker(
          api: FakeDriveUploadApi(),
          repo: repo,
          db: db,
          enumeratorIdentifier: () => 'test@example.com')),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(driveUploadNotifierProvider.notifier);
    final first = await notifier.stream
        .firstWhere((s) => s.jobs.length == 50 && s.totals?.activeCount == 103);
    expect(first.pendingCount, 102);
    expect(first.totalPendingBytes, 10200);
    expect(first.failedCount, 1);
    expect(first.isUploading, isTrue);
    expect(first.jobs.any((j) => j.id == 'j0102'), isFalse);
    expect(first.hasMore, isTrue);
    final secondFuture = notifier.stream
        .firstWhere((s) => s.jobs.length == 100 && !s.isLoadingMore);
    await notifier.loadMore();
    final second = await secondFuture;
    expect(second.jobs.map((j) => j.id).toSet(), hasLength(100));
    final completedFuture = notifier.stream.firstWhere(
        (s) => s.totals?.activeCount == 102 && s.jobs.first.id == 'j0001');
    await repo.markCompleted('j0000', driveFileId: 'uploaded');
    await completedFuture;
    final lastFuture =
        notifier.stream.firstWhere((s) => s.jobs.length == 102 && !s.hasMore);
    await notifier.loadMore();
    final last = await lastFuture;
    expect(last.jobs.any((j) => j.status == DriveUploadJobStatus.completed),
        isFalse);
    expect(await repo.getJobsForAssignment('a1'), hasLength(603));
  });

  test('pendingCount reflects queue', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriveUploadRepository(db);
    await repo.insertJob(
      id: 'j1',
      assignmentId: 'a1',
      filePath: '/p1.jpg',
      fileType: DriveFileType.photo,
      fileName: 'p1.jpg',
      fileSizeBytes: 100,
      capturedAt: DateTime(2026),
    );

    final container = ProviderContainer(overrides: [
      driveUploadRepoProvider.overrideWithValue(repo),
      driveUploadWorkerProvider.overrideWithValue(
        DriveUploadWorker(
          api: FakeDriveUploadApi(),
          repo: repo,
          db: db,
          enumeratorIdentifier: () => 'test@example.com',
        ),
      ),
    ]);
    addTearDown(container.dispose);

    // Trigger notifier creation (subscribes to the stream).
    container.read(driveUploadNotifierProvider);

    // Wait for the notifier's own state stream to emit a non-empty job list.
    final state = await container
        .read(driveUploadNotifierProvider.notifier)
        .stream
        .firstWhere((s) => s.jobs.isNotEmpty);

    expect(state.pendingCount, 1);
  });
}
