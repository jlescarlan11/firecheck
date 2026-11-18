import 'package:firecheck/core/db/database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum TransferPhase { queued, uploading, confirming, completed, failed }

class UploadTransferProgress {
  const UploadTransferProgress({
    required this.job,
    required this.sent,
    required this.phase,
  });
  final DriveUploadJob job;
  final int sent;
  final TransferPhase phase;

  // Reserve 100% for the server's successful completion response.
  int get percent => phase == TransferPhase.completed
      ? 100
      : job.fileSizeBytes <= 0
          ? 0
          : (sent * 100 ~/ job.fileSizeBytes).clamp(0, 99);

  String get label => labelAt(percent);

  String labelAt(int displayedPercent) => switch (phase) {
        TransferPhase.queued => 'Waiting · 0%',
        TransferPhase.uploading => '$displayedPercent%',
        TransferPhase.confirming => '$displayedPercent% · Confirming…',
        TransferPhase.completed =>
          displayedPercent < 100 ? '$displayedPercent%' : '100% · Uploaded',
        TransferPhase.failed => '$displayedPercent% · Retry needed',
      };
}

/// Live foreground transfer data. Durable job status remains in SQLite;
/// resumed gateway uploads restore their byte count from the server offset.
class UploadTransferTracker
    extends StateNotifier<Map<String, UploadTransferProgress>> {
  UploadTransferTracker() : super(const {});

  int sentFor(String id) => state[id]?.sent ?? 0;

  void clear() {
    if (mounted) state = const {};
  }

  void update(DriveUploadJob job, int sent, TransferPhase phase) {
    if (!mounted) return;
    final next = UploadTransferProgress(job: job, sent: sent, phase: phase);
    final previous = state[job.id];
    if (previous?.percent == next.percent && previous?.phase == phase) return;
    state = {...state, job.id: next};
  }
}

final uploadTransferProgressProvider = StateNotifierProvider<
    UploadTransferTracker,
    Map<String, UploadTransferProgress>>((ref) => UploadTransferTracker());
