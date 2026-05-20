import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_audit_repository.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/drive_upload_worker.dart' show sanitizeDriveFolderName;
import 'package:firecheck/features/assignment/data/assignment_repository.dart';

/// Result of finalizing the post-drain bookkeeping for an assignment's
/// Drive upload. Both the foreground UI path and the background WorkManager
/// isolate funnel through [FinalizeAssignmentUploadUseCase] so they produce
/// identical persisted state regardless of which one drained the queue.
sealed class DriveUploadOutcome {
  const DriveUploadOutcome({required this.assignmentId});
  final String assignmentId;
}

/// All jobs completed; assignment row + audit row have been written.
final class DriveUploadSucceeded extends DriveUploadOutcome {
  const DriveUploadSucceeded({
    required super.assignmentId,
    required this.folderPath,
    required this.completedCount,
    required this.confirmedAt,
  });
  final String folderPath;
  final int completedCount;
  final DateTime confirmedAt;
}

/// Some jobs are still failed/dead; nothing was persisted. Caller decides
/// how to surface the partial state.
final class DriveUploadIncomplete extends DriveUploadOutcome {
  const DriveUploadIncomplete({
    required super.assignmentId,
    required this.completedCount,
    required this.failedCount,
  });
  final int completedCount;
  final int failedCount;
}

/// No jobs exist for this assignment, or the assignment row is missing.
final class DriveUploadEmpty extends DriveUploadOutcome {
  const DriveUploadEmpty({required super.assignmentId});
}

class FinalizeAssignmentUploadUseCase {
  FinalizeAssignmentUploadUseCase({
    required AppDatabase db,
    required DriveUploadRepository repo,
    required AssignmentRepository assignmentRepo,
    required DriveUploadAuditRepository auditRepo,
    DateTime Function() now = DateTime.now,
    String? Function()? enumeratorIdentifier,
  })  : _db = db,
        _repo = repo,
        _assignmentRepo = assignmentRepo,
        _auditRepo = auditRepo,
        _now = now,
        _enumeratorIdentifier = enumeratorIdentifier;

  final AppDatabase _db;
  final DriveUploadRepository _repo;
  final AssignmentRepository _assignmentRepo;
  final DriveUploadAuditRepository _auditRepo;
  final DateTime Function() _now;

  /// Resolves the same per-enumerator Drive subfolder name the worker uses
  /// when uploading. When non-null, the persisted [folderPath] mirrors the
  /// worker's `firecheck/output/<enumerator>/<assignmentFolderName>/`
  /// layout. When null (tests, environments without auth), the legacy
  /// `firecheck/<assignmentFolderName>/` shape is written.
  final String? Function()? _enumeratorIdentifier;

  /// Inspects the job queue for [assignmentId], persists the upload result
  /// on the assignment row, and records an audit entry when every job has
  /// completed. Returns the outcome so the caller can update UI / logs.
  ///
  /// Safe to invoke from any isolate that has an [AppDatabase] handle.
  /// Re-finalizing an already-finalized assignment is a no-op as long as
  /// the job set hasn't changed, since the writes are idempotent overwrites.
  Future<DriveUploadOutcome> execute({
    required String assignmentId,
    String? uploaderId,
  }) async {
    final jobs = await _repo.getJobsForAssignment(assignmentId);
    if (jobs.isEmpty) {
      return DriveUploadEmpty(assignmentId: assignmentId);
    }

    final completed = jobs
        .where((j) => j.status == DriveUploadJobStatus.completed)
        .length;
    final failed = jobs
        .where((j) =>
            j.status == DriveUploadJobStatus.failed ||
            j.status == DriveUploadJobStatus.dead,)
        .length;

    if (completed == 0 || failed > 0) {
      return DriveUploadIncomplete(
        assignmentId: assignmentId,
        completedCount: completed,
        failedCount: failed,
      );
    }

    final folderName = await _resolveFolderName(assignmentId);
    if (folderName == null) {
      // The assignment row itself is missing — nothing to confirm against.
      return DriveUploadEmpty(assignmentId: assignmentId);
    }

    final confirmedAt = _now();
    final folderPath = _buildFolderPath(folderName);

    await _assignmentRepo.setDriveUploadResult(
      assignmentId: assignmentId,
      driveFolderPath: folderPath,
      driveFolderUrl: '',
      driveUploadConfirmedAt: confirmedAt,
    );

    if (uploaderId != null) {
      await _auditRepo.record(
        assignmentId: assignmentId,
        uploadedBy: uploaderId,
        driveFolderPath: folderPath,
        driveFolderUrl: '',
        fileCount: completed,
      );
    }

    return DriveUploadSucceeded(
      assignmentId: assignmentId,
      folderPath: folderPath,
      completedCount: completed,
      confirmedAt: confirmedAt,
    );
  }

  /// Finalizes every assignment that has at least one completed job and no
  /// recorded confirmation. Used by the background WorkManager isolate,
  /// which doesn't know which assignment(s) had jobs drained this tick.
  Future<List<DriveUploadOutcome>> executePending({String? uploaderId}) async {
    final rows = await _db.customSelect(
      'SELECT DISTINCT j.assignment_id '
      'FROM drive_upload_jobs j '
      'INNER JOIN assignments a ON a.id = j.assignment_id '
      'WHERE j.status = ? AND a.drive_upload_confirmed_at IS NULL',
      variables: [Variable.withString(DriveUploadJobStatus.completed)],
    ).get();
    final ids = rows
        .map((r) => r.read<String>('assignment_id'))
        .toList(growable: false);

    final outcomes = <DriveUploadOutcome>[];
    for (final id in ids) {
      outcomes.add(
        await execute(assignmentId: id, uploaderId: uploaderId),
      );
    }
    return outcomes;
  }

  /// Returns the assignment-scoped folder name used in the Drive path. Falls
  /// back to the assignment id when `assignments.name` is null — UUID-named
  /// and legacy assignments are valid runtime cases (the worker uses the
  /// same fallback), and missing the fallback used to misreport successful
  /// uploads as Empty.
  Future<String?> _resolveFolderName(String assignmentId) async {
    final row = await (_db.select(_db.assignments)
          ..where((t) => t.id.equals(assignmentId)))
        .getSingleOrNull();
    if (row == null) return null;
    return row.name ?? row.id;
  }

  String _buildFolderPath(String folderName) {
    final resolver = _enumeratorIdentifier;
    if (resolver == null) return 'firecheck/$folderName/';
    final enumerator =
        sanitizeDriveFolderName(resolver()) ?? 'unknown-enumerator';
    return 'firecheck/output/$enumerator/$folderName/';
  }
}
