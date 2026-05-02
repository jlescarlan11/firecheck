// test/features/upload/upload_queue_notifier_test.dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:firecheck/core/drive/fake_drive_upload_api.dart';
import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pendingCount reflects queue', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriveUploadRepository(db);
    await repo.insertJob(
      id: 'j1', assignmentId: 'a1', filePath: '/p1.jpg',
      fileType: DriveFileType.photo, fileName: 'p1.jpg',
      fileSizeBytes: 100, capturedAt: DateTime(2026),
    );

    final container = ProviderContainer(overrides: [
      driveUploadRepoProvider.overrideWithValue(repo),
      driveUploadWorkerProvider.overrideWithValue(
        DriveUploadWorker(
          api: FakeDriveUploadApi(),
          repo: repo,
          db: db,
          rootFolderId: 'root',
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
