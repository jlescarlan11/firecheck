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
  List<SyncJob> _latestJobs = const [];
  Set<String> _previousTerminalIds = {};

  /// Keep old successful/failed jobs out of this attempt without comparing
  /// wall-clock timestamps: SQLite stores createdAt with second precision.
  /// Existing pending jobs still belong to this attempt and must be counted.
  void beginUpload() {
    _previousTerminalIds = {
      for (final job in _latestJobs)
        if (job.status == 'success' || job.status == 'dead') job.id,
    };
    _uploading = true;
    _onJobs(_latestJobs);
  }

  void beginDriveUpload() {
    _uploading = false;
    state = const InProgress(done: 0, total: 0, label: 'Uploading files…');
  }

  void reset() {
    _uploading = false;
    _previousTerminalIds.clear();
    state = const Idle();
  }

  void _onJobs(List<SyncJob> allJobs) {
    _latestJobs = allJobs;
    if (!_uploading) return;
    // A retried terminal job becomes part of this attempt again.
    for (final job in allJobs) {
      if (job.status != 'success' && job.status != 'dead') {
        _previousTerminalIds.remove(job.id);
      }
    }
    final jobs =
        allJobs.where((job) => !_previousTerminalIds.contains(job.id)).toList();
    if (jobs.isEmpty) {
      // Wait for enqueueing. The orchestrator explicitly ends this phase
      // even when there are no new sync jobs (for example, a Drive-only retry).
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
