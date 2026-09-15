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
    this.totals,
    this.isLoadingMore = false,
  });

  final List<DriveUploadJob> jobs;
  final UploadQueueTotals? totals;
  final bool isLoadingMore;
  List<DriveUploadJob> get visibleJobs => jobs
      .where((j) => j.status != DriveUploadJobStatus.completed)
      .toList(growable: false);
  bool get hasMore => (totals?.activeCount ?? jobs.length) > jobs.length;
  int get failedCount =>
      totals?.failedCount ??
      jobs
          .where(
            (j) =>
                j.status == DriveUploadJobStatus.failed ||
                j.status == DriveUploadJobStatus.dead,
          )
          .length;
  DriveUploadState copyWith({
    List<DriveUploadJob>? jobs,
    UploadQueueTotals? totals,
    bool? isLoadingMore,
  }) =>
      DriveUploadState(
        jobs: jobs ?? this.jobs,
        totals: totals ?? this.totals,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      );

  int get pendingCount =>
      totals?.pendingCount ??
      jobs
          .where(
            (j) =>
                j.status == DriveUploadJobStatus.pending ||
                j.status == DriveUploadJobStatus.failed ||
                j.status == DriveUploadJobStatus.dead,
          )
          .length;

  int get totalPendingBytes =>
      totals?.pendingBytes ??
      jobs
          .where(
            (j) =>
                j.status == DriveUploadJobStatus.pending ||
                j.status == DriveUploadJobStatus.failed ||
                j.status == DriveUploadJobStatus.dead,
          )
          .fold(0, (sum, j) => sum + j.fileSizeBytes);

  int get uploadingCount =>
      totals?.uploadingCount ??
      jobs.where((j) => j.status == DriveUploadJobStatus.uploading).length;

  bool get isUploading => uploadingCount > 0;
}

class DriveUploadNotifier extends StateNotifier<DriveUploadState> {
  DriveUploadNotifier({
    required DriveUploadRepository repo,
    required DriveUploadWorker worker,
  }) : super(const DriveUploadState(jobs: [])) {
    _repo = repo;
    _worker = worker;
    _totalsSub = repo.watchQueueTotals().listen((totals) {
      state = state.copyWith(totals: totals);
    });
    unawaited(_watchPage());
  }

  /// Use in widget tests to seed a static state without subscribing to Drift.
  @visibleForTesting
  DriveUploadNotifier.seeded(super.initialState);

  static const pageSize = 50;
  int _limit = pageSize;
  int _pageVersion = 0;
  StreamSubscription<UploadQueueTotals>? _totalsSub;

  Future<void> _watchPage() async {
    final version = ++_pageVersion;
    await _sub?.cancel();
    if (!mounted || version != _pageVersion) return;
    _sub = _repo!.watchQueue(limit: _limit).listen((jobs) {
      if (!mounted || version != _pageVersion) return;
      state = state.copyWith(jobs: jobs, isLoadingMore: false);
    });
  }

  Future<void> loadMore() async {
    if (_repo == null || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    _limit += pageSize;
    await _watchPage();
  }

  DriveUploadRepository? _repo;
  DriveUploadWorker? _worker;
  StreamSubscription<List<DriveUploadJob>>? _sub;

  Future<void> uploadAll() async {
    assert(
      _repo != null && _worker != null,
      'uploadAll() called on a seeded test notifier',
    );
    await _repo!.resetFailedToPending();
    await _worker!.drain();
  }

  Future<void> retryJob(String jobId) async {
    assert(
      _repo != null && _worker != null,
      'retryJob() called on a seeded test notifier',
    );
    await _repo!.resetForRetry(jobId);
    await _worker!.drain();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _totalsSub?.cancel();
    super.dispose();
  }
}
