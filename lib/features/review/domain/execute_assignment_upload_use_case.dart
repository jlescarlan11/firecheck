import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
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
    this.sharedDb,
  })  : _assignmentRepository = assignmentRepository,
        _auditRepository = auditRepository,
        _startUploadUseCase = startUploadUseCase,
        _enqueueAssignmentUseCase = enqueueAssignmentUseCase,
        _driveUploadRepository = driveUploadRepository,
        _driveUploadWorker = driveUploadWorker,
        _finalizeAssignmentUploadUseCase = finalizeAssignmentUploadUseCase,
        _progressController = progressController;

  final AppDatabase? sharedDb;
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
    final id = state.assignmentId;
    final assignment =
        id == null ? null : await _assignmentRepository.getAssignment(id);
    if (assignment == null) {
      debugPrint('[Upload] no current assignment — aborting');
      return const UploadFlowNoAssignment();
    }

    if (assignment.closedRemotely) {
      return UploadFlowSupabaseFailed(StateError('This map is closed.'));
    }
    final db = sharedDb;
    if (db != null && currentUserId != null) {
      final capability = await (db.select(db.sharedMapCursors)
            ..where(
              (t) =>
                  t.accountId.equals(currentUserId) &
                  t.assignmentId.equals(assignment.id),
            ))
          .getSingleOrNull();
      if (capability != null) {
        try {
          final failed = await _runSupabasePhase(assignment.id);
          if (failed != null) return failed;
          return await _syncState(db, assignment.id);
        } finally {
          _progressController.reset();
        }
      }
    }
    if (!await _assignmentRepository.hasChangesToUpload(assignment.id)) {
      return UploadFlowSucceeded(
        folderPath: assignment.driveFolderPath ?? '',
        confirmedAt: assignment.driveUploadConfirmedAt!,
      );
    }
    final cancellation = await _runConfirmations(
      state: state,
      assignmentId: assignment.id,
      currentUserId: currentUserId,
      confirmer: confirmer,
    );
    if (cancellation != null) return cancellation;

    final latest = await _assignmentRepository.getAssignment(assignment.id);
    if (latest == null || latest.closedRemotely) {
      return UploadFlowSupabaseFailed(
        StateError('This map is unavailable or closed.'),
      );
    }
    try {
      final supabase = await _runSupabasePhase(assignment.id);
      if (supabase != null) return supabase;
      if (db != null) {
        final sync = await _syncState(db, assignment.id);
        if (sync.pending > 0 ||
            sync.conflicts > 0 ||
            sync.pendingPhotos > 0 ||
            sync.pendingGeometry > 0) {
          return UploadFlowSupabaseFailed(
            StateError('Some changes are still pending sync or review.'),
          );
        }
      }
      _progressController.beginDriveUpload();
      return await _runDrivePhase(
        assignmentId: assignment.id,
        currentUserId: currentUserId,
      );
    } finally {
      // Drive completion is independent of sync_jobs. Always leave the
      // progress view so success, retry, and empty results are visible.
      _progressController.reset();
    }
  }

  Future<UploadFlowSynced> _syncState(
    AppDatabase db,
    String assignmentId,
  ) async {
    final rows = await (db.select(db.submissions).join([
      innerJoin(
        db.features,
        db.features.id.equalsExp(db.submissions.featureId),
      ),
    ])
          ..where(db.features.assignmentId.equals(assignmentId)))
        .map((r) => r.readTable(db.submissions))
        .get();
    final photos = await (db.select(db.photos).join([
      innerJoin(
        db.submissions,
        db.submissions.id.equalsExp(db.photos.submissionId),
      ),
      innerJoin(
        db.features,
        db.features.id.equalsExp(db.submissions.featureId),
      ),
    ])
          ..where(
            db.features.assignmentId.equals(assignmentId) &
                db.photos.uploadStatus.equals('uploaded').not() &
                db.submissions.syncStatus.isIn([
                  'ready_to_upload',
                  'queued',
                  'uploaded',
                  'awaiting_user_resolution',
                ]),
          ))
        .get();
    final geometry = await (db.select(db.featureGeometryRevisions).join([
      innerJoin(
        db.features,
        db.features.id.equalsExp(db.featureGeometryRevisions.featureId),
      ),
    ])
          ..where(
            db.features.assignmentId.equals(assignmentId) &
                db.featureGeometryRevisions.syncStatus
                    .isNotIn(['uploaded', 'discarded']),
          ))
        .get();
    final frozen = await (db.select(db.syncJobs)
          ..where(
            (t) =>
                t.entityType.equals('attribution_upload') &
                t.entityId.isIn(rows.map((s) => s.id).toList()),
          ))
        .get();
    final finalizedIds = frozen.map((job) => job.entityId).toSet();
    return UploadFlowSynced(
      pendingGeometry: geometry.length,
      pendingPhotos: photos.length,
      pending: rows
          .where(
            (s) =>
                {'ready_to_upload', 'queued'}.contains(s.syncStatus) ||
                (s.syncStatus == 'in_progress' && finalizedIds.contains(s.id)),
          )
          .length,
      conflicts:
          rows.where((s) => s.syncStatus == 'awaiting_user_resolution').length,
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
    String assignmentId,
  ) async {
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
      expectedOwnerId: currentUserId,
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
