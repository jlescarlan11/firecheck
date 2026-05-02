// lib/features/upload/presentation/upload_queue_notifier.dart
import 'dart:async';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DriveUploadState {
  const DriveUploadState({
    required this.jobs,
  });

  final List<DriveUploadJob> jobs;

  int get pendingCount => jobs
      .where((j) =>
          j.status == DriveUploadJobStatus.pending ||
          j.status == DriveUploadJobStatus.failed ||
          j.status == DriveUploadJobStatus.dead)
      .length;

  int get totalPendingBytes => jobs
      .where((j) =>
          j.status == DriveUploadJobStatus.pending ||
          j.status == DriveUploadJobStatus.failed ||
          j.status == DriveUploadJobStatus.dead)
      .fold(0, (sum, j) => sum + j.fileSizeBytes);

  int get uploadingCount =>
      jobs.where((j) => j.status == DriveUploadJobStatus.uploading).length;

  bool get isUploading =>
      jobs.any((j) => j.status == DriveUploadJobStatus.uploading);
}

class DriveUploadNotifier extends StateNotifier<DriveUploadState> {
  DriveUploadNotifier({
    required DriveUploadRepository repo,
    required DriveUploadWorker worker,
  })  : super(const DriveUploadState(jobs: [])) {
    _repo = repo;
    _worker = worker;
    _sub = repo.watchQueue().listen((jobs) {
      state = DriveUploadState(jobs: jobs);
    });
  }

  /// Use in widget tests to seed a static state without subscribing to Drift.
  @visibleForTesting
  DriveUploadNotifier.seeded(DriveUploadState initialState)
      : super(initialState);

  late final DriveUploadRepository _repo;
  late final DriveUploadWorker _worker;
  StreamSubscription<List<DriveUploadJob>>? _sub;

  Future<void> uploadAll() async {
    await _repo.resetFailedToPending();
    await _worker.drain();
  }

  Future<void> retryJob(String jobId) async {
    await _repo.resetForRetry(jobId);
    await _worker.drain();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
