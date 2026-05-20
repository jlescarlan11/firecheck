import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:firecheck/features/review/domain/drive_upload_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State holder for the Review screen's "Drive upload" confirmation card.
///
/// Lifecycle:
/// * On screen entry, `initFromDb` hydrates `Success` from any persisted
///   prior upload so re-entries show "already uploaded" without re-doing
///   work.
/// * The queue-based pipeline ([ExecuteAssignmentUploadUseCase]) drives
///   the actual upload and calls [applyQueueSuccess] / [applyQueueFailure]
///   on completion.
class DriveUploadNotifier extends StateNotifier<DriveUploadState> {
  DriveUploadNotifier({
    required AssignmentRepository assignmentRepository,
  })  : _assignmentRepository = assignmentRepository,
        super(const DriveUploadIdle());

  final AssignmentRepository _assignmentRepository;
  String? _assignmentId;

  String _formatReferenceId(String id) =>
      'ASN-${id.substring(0, id.length.clamp(0, 8)).toUpperCase()}';

  /// Reads persisted Drive upload result from DB. Call once after construction.
  Future<void> initFromDb(String assignmentId) async {
    _assignmentId = assignmentId;
    try {
      final result =
          await _assignmentRepository.getDriveUploadResult(assignmentId);
      if (!mounted) return;
      if (result != null) {
        state = DriveUploadSuccess(
          folderPath: result.folderPath,
          folderUrl: result.folderUrl,
          referenceId: _formatReferenceId(assignmentId),
          confirmedAt: result.confirmedAt,
        );
      }
    } catch (_) {
      if (!mounted) return;
      state = const DriveUploadFailure(
        message: 'Could not load upload status. Please try again.',
        canRetry: true,
      );
    }
  }

  /// Called by the queue-based upload path after [DriveUploadWorker.drain]
  /// + bookkeeping have completed successfully.
  void applyQueueSuccess({
    required String folderPath,
    required DateTime confirmedAt,
  }) {
    final referenceId = _assignmentId != null
        ? _formatReferenceId(_assignmentId!)
        : '';
    state = DriveUploadSuccess(
      folderPath: folderPath,
      folderUrl: '',
      referenceId: referenceId,
      confirmedAt: confirmedAt,
    );
  }

  void applyQueueFailure(String message, {bool canRetry = true}) {
    state = DriveUploadFailure(message: message, canRetry: canRetry);
  }

  /// Test-only: force a specific state.
  void debugSetState(DriveUploadState s) => state = s;
}
