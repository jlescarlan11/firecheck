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
  // Timestamp captured the moment beginUpload() fires. Jobs older than
  // this (e.g. dead retries from previous attempts) are filtered out so
  // the progress bar reflects only jobs created by the current session.
  DateTime? _sessionStart;

  /// Caller flips this on right before triggering the worker. While true,
  /// the controller computes InProgress/Completed; while false, all
  /// emissions are ignored (we stay Idle).
  void beginUpload() {
    _uploading = true;
    // Subtract a small skew so jobs inserted inside the same millisecond
    // as this call still count toward "this session".
    _sessionStart =
        DateTime.now().subtract(const Duration(milliseconds: 100));
    state = const InProgress(done: 0, total: 0);
  }

  void reset() {
    _uploading = false;
    _sessionStart = null;
    state = const Idle();
  }

  void _onJobs(List<SyncJob> allJobs) {
    if (!_uploading) return;
    final sessionStart = _sessionStart;
    final jobs = sessionStart == null
        ? allJobs
        : allJobs.where((j) => !j.createdAt.isBefore(sessionStart)).toList();
    if (jobs.isEmpty) {
      // No session jobs yet — beginUpload() fired but the worker hasn't
      // enqueued rows. Hold InProgress; collapsing to Completed here would
      // flash a stale success card whenever a second upload begins while
      // the previous attempt's success rows are still in sync_jobs (they
      // get filtered out by sessionStart, leaving the filtered list empty).
      state = const InProgress(done: 0, total: 0);
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
