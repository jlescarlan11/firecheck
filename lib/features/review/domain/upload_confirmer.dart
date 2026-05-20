import 'package:firecheck/core/drive/drive_upload_audit_repository.dart';

/// Strategy for the human-in-the-loop confirmation gates that protect the
/// review-page upload pipeline.
///
/// The widget injects a dialog-backed implementation; tests inject a
/// canned "always-yes" or "always-no" double. Keeping this off
/// [ExecuteAssignmentUploadUseCase] lets the use case stay free of
/// `BuildContext` / Flutter dependencies.
abstract class UploadConfirmer {
  /// Asked when the assignment has unsurveyed features. Returning false
  /// aborts the upload.
  Future<bool> confirmPartial({
    required int unsurveyedCount,
    required int totalFeatures,
  });

  /// Asked when the audit probe found one or more prior uploads for the
  /// assignment. Returning false aborts the upload.
  Future<bool> confirmOverwrite({
    required List<DriveUploadAudit> priorUploads,
    required String? currentUserId,
  });

  /// Asked when the audit probe couldn't reach the server, so we can't
  /// tell whether someone else has already uploaded. Returning false
  /// aborts the upload.
  Future<bool> confirmUnverified();
}
