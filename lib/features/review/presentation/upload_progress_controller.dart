import 'dart:async';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/review/domain/upload_progress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// StateNotifier driving the Review screen's render mode based on
/// the live sync_jobs stream for the current assignment.
class UploadProgressController extends StateNotifier<UploadProgress> {
  UploadProgressController({required Stream<List<SyncJob>> jobsStream})
      : super(const Idle()) {
    _sub = jobsStream.listen(_onJobs);
  }

  late final StreamSubscription<List<SyncJob>> _sub;
  bool _uploading = false;

  /// Caller flips this on right before triggering the worker. While true,
  /// the controller computes InProgress/Completed; while false, all
  /// emissions are ignored (we stay Idle).
  void beginUpload() {
    _uploading = true;
    state = const InProgress(done: 0, total: 0);
  }

  void reset() {
    _uploading = false;
    state = const Idle();
  }

  void _onJobs(List<SyncJob> jobs) {
    if (!_uploading) return;
    if (jobs.isEmpty) {
      state = const Completed(failedCount: 0);
      return;
    }
    final done = jobs.where((j) => j.status == 'success').length;
    final dead = jobs.where((j) => j.status == 'dead').length;
    final terminal = done + dead;
    if (terminal == jobs.length) {
      state = Completed(failedCount: dead);
      return;
    }
    state = InProgress(done: done, total: jobs.length);
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
