import 'package:firecheck/core/drive/drive_upload_audit_repository.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:firecheck/core/drive/enqueue_assignment_use_case.dart';
import 'package:firecheck/core/drive/finalize_assignment_upload_use_case.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/domain/upload_confirmer.dart';
import 'package:firecheck/features/review/domain/upload_flow_outcome.dart';
import 'package:firecheck/features/review/presentation/sub/start_upload_use_case.dart';
import 'package:firecheck/features/review/presentation/upload_progress_controller.dart';
import 'package:flutter/foundation.dart';

/// Orchestrates the review-page upload pipeline end to end:
///
///   1. resolve current assignment
///   2. partial-data confirmation gate
///   3. prior-upload audit probe + matching confirmation gate
///   4. Supabase finalize + sync-trigger
///   5. Drive enqueue → drain → finalize bookkeeping
///
/// Lives outside the widget so it survives screen pop mid-drain and is
/// straightforward to test: pass in a stub [UploadConfirmer] and assert
/// on the returned [UploadFlowOutcome].
class ExecuteAssignmentUploadUseCase {
  ExecuteAssignmentUploadUseCase({
    required AssignmentRepository assignmentRepository,
    required DriveUploadAuditRepository auditRepository,
    required StartUploadUseCase startUploadUseCase,
    required EnqueueAssignmentUseCase enqueueAssignmentUseCase,
    required DriveUploadRepository driveUploadRepository,
    required DriveUploadWorker driveUploadWorker,
    required FinalizeAssignmentUploadUseCase finalizeAssignmentUploadUseCase,
    required UploadProgressController progressController,
  })  : _assignmentRepository = assignmentRepository,
        _auditRepository = auditRepository,
        _startUploadUseCase = startUploadUseCase,
        _enqueueAssignmentUseCase = enqueueAssignmentUseCase,
        _driveUploadRepository = driveUploadRepository,
        _driveUploadWorker = driveUploadWorker,
        _finalizeAssignmentUploadUseCase = finalizeAssignmentUploadUseCase,
        _progressController = progressController;

  final AssignmentRepository _assignmentRepository;
  final DriveUploadAuditRepository _auditRepository;
  final StartUploadUseCase _startUploadUseCase;
  final EnqueueAssignmentUseCase _enqueueAssignmentUseCase;
  final DriveUploadRepository _driveUploadRepository;
  final DriveUploadWorker _driveUploadWorker;
  final FinalizeAssignmentUploadUseCase _finalizeAssignmentUploadUseCase;
  final UploadProgressController _progressController;

  Future<UploadFlowOutcome> execute({
    required ReviewState state,
    required String? currentUserId,
    required UploadConfirmer confirmer,
  }) async {
    final assignment = await _assignmentRepository.getCurrentAssignment();
    if (assignment == null) {
      debugPrint('[Upload] no current assignment — aborting');
      return const UploadFlowNoAssignment();
    }

    final cancellation = await _runConfirmations(
      state: state,
      assignmentId: assignment.id,
      currentUserId: currentUserId,
      confirmer: confirmer,
    );
    if (cancellation != null) return cancellation;

    final supabase = await _runSupabasePhase(assignment.id);
    if (supabase != null) return supabase;

    return _runDrivePhase(
      assignmentId: assignment.id,
      currentUserId: currentUserId,
    );
  }

  Future<UploadFlowCancelled?> _runConfirmations({
    required ReviewState state,
    required String assignmentId,
    required String? currentUserId,
    required UploadConfirmer confirmer,
  }) async {
    final unsurveyedCount = state.warnings
        .where((w) => w.code == 'feature_has_no_finalized_submission')
        .length;
    if (unsurveyedCount > 0) {
      final ok = await confirmer.confirmPartial(
        unsurveyedCount: unsurveyedCount,
        totalFeatures: state.summary.totalFeatures,
      );
      if (!ok) {
        debugPrint('[Upload] user cancelled partial upload');
        return const UploadFlowCancelled(
          UploadFlowCancellationReason.partial,
        );
      }
    }

    final probe = await _auditRepository.listForAssignment(assignmentId);
    switch (probe) {
      case AuditProbeAvailable(:final audits) when audits.isNotEmpty:
        // Skip the dialog when every prior upload was made by the
        // current user. A self re-upload is the expected workflow:
        // edit + upload again. The dialog still appears the moment a
        // cross-enumerator upload exists, so users get a heads-up
        // before stomping on someone else's submission.
        final allByCurrentUser = currentUserId != null &&
            audits.every((u) => u.uploadedBy == currentUserId);
        if (allByCurrentUser) {
          debugPrint(
            '[Upload] prior uploads are all by current user — skipping confirm',
          );
          break;
        }
        final ok = await confirmer.confirmOverwrite(
          priorUploads: audits,
          currentUserId: currentUserId,
        );
        if (!ok) {
          debugPrint('[Upload] user cancelled re-upload');
          return const UploadFlowCancelled(
            UploadFlowCancellationReason.overwrite,
          );
        }
      case AuditProbeUnavailable():
        final ok = await confirmer.confirmUnverified();
        if (!ok) {
          debugPrint('[Upload] user cancelled unverified upload');
          return const UploadFlowCancelled(
            UploadFlowCancellationReason.unverified,
          );
        }
      case AuditProbeAvailable():
        break;
    }
    return null;
  }

  Future<UploadFlowSupabaseFailed?> _runSupabasePhase(
      String assignmentId,) async {
    debugPrint('[Upload] supabase phase begin');
    _progressController.beginUpload();
    try {
      final result = await _startUploadUseCase.execute(assignmentId);
      debugPrint(
        '[Upload] supabase finalized ${result.finalizedCount} submission(s)',
      );
      return null;
    } catch (e, st) {
      debugPrint('[Upload] supabase phase failed: $e\n$st');
      _progressController.reset();
      return UploadFlowSupabaseFailed(e);
    }
  }

  Future<UploadFlowOutcome> _runDrivePhase({
    required String assignmentId,
    required String? currentUserId,
  }) async {
    debugPrint('[Upload] drive phase begin');
    final enqueued = await _enqueueAssignmentUseCase.execute(
      assignmentId: assignmentId,
    );
    debugPrint('[Upload] drive enqueued $enqueued new job(s)');

    final allJobs =
        await _driveUploadRepository.getJobsForAssignment(assignmentId);
    if (allJobs.isEmpty) {
      return const UploadFlowEmpty();
    }

    await _driveUploadWorker.drain();

    final outcome = await _finalizeAssignmentUploadUseCase.execute(
      assignmentId: assignmentId,
      uploaderId: currentUserId,
    );

    return switch (outcome) {
      DriveUploadSucceeded(:final folderPath, :final confirmedAt) =>
        UploadFlowSucceeded(
          folderPath: folderPath,
          confirmedAt: confirmedAt,
        ),
      DriveUploadIncomplete(:final completedCount, :final failedCount) =>
        UploadFlowIncomplete(
          completedCount: completedCount,
          failedCount: failedCount,
        ),
      DriveUploadEmpty() => const UploadFlowEmpty(),
    };
  }
}
