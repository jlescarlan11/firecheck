import 'dart:async';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/review/domain/upload_progress.dart';
import 'package:firecheck/features/review/presentation/upload_progress_controller.dart';
import 'package:flutter_test/flutter_test.dart';

SyncJob _job(String id, String status) => SyncJob(
      id: id,
      entityType: 'submission',
      entityId: 'e-$id',
      status: status,
      attempts: 0,
      blocksOnSubmissionId: null,
      lastError: null,
      nextRetryAt: null,
      createdAt: DateTime(2026, 4, 27),
    );

void main() {
  test('starts Idle', () {
    final ctrl = StreamController<List<SyncJob>>();
    addTearDown(ctrl.close);
    final notifier = UploadProgressController(jobsStream: ctrl.stream);
    expect(notifier.state, isA<Idle>());
  });

  test('beginUpload + non-empty stream emits InProgress with done/total', () async {
    final ctrl = StreamController<List<SyncJob>>();
    addTearDown(ctrl.close);
    final notifier = UploadProgressController(jobsStream: ctrl.stream);
    notifier.beginUpload();

    ctrl.add([_job('a', 'pending'), _job('b', 'in_progress'), _job('c', 'success')]);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(notifier.state, isA<InProgress>());
    final p = notifier.state as InProgress;
    expect(p.done, 1);
    expect(p.total, 3);
  });

  test('all-success → Completed(failedCount: 0)', () async {
    final ctrl = StreamController<List<SyncJob>>();
    addTearDown(ctrl.close);
    final notifier = UploadProgressController(jobsStream: ctrl.stream);
    notifier.beginUpload();
    ctrl.add([_job('a', 'success'), _job('b', 'success')]);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(notifier.state, isA<Completed>());
    expect((notifier.state as Completed).failedCount, 0);
  });

  test('any dead → Completed(failedCount: N)', () async {
    final ctrl = StreamController<List<SyncJob>>();
    addTearDown(ctrl.close);
    final notifier = UploadProgressController(jobsStream: ctrl.stream);
    notifier.beginUpload();
    ctrl.add([_job('a', 'success'), _job('b', 'dead')]);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(notifier.state, isA<Completed>());
    expect((notifier.state as Completed).failedCount, 1);
  });

  test('reset() returns to Idle', () async {
    final ctrl = StreamController<List<SyncJob>>();
    addTearDown(ctrl.close);
    final notifier = UploadProgressController(jobsStream: ctrl.stream);
    notifier.beginUpload();
    ctrl.add([_job('a', 'success')]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    notifier.reset();
    expect(notifier.state, isA<Idle>());
  });
}
