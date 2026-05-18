// lib/core/drive/drive_api.dart
import 'dart:typed_data';

import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';

abstract interface class DriveApi {
  /// Lists assignment subfolders directly under /firecheck/, readable by
  /// the signed-in user. Each subfolder name is treated as the assignment id.
  Future<List<DriveAssignment>> listAssignments();

  /// Sum of all shapefile component sizes in bytes from Drive file metadata.
  Future<int> getTotalSize(String assignmentId);

  /// Streams download events for all shapefile components in the folder.
  Stream<DriveDownloadEvent> downloadShapefiles(String assignmentId);

  /// Fetches only the `field_requirements.txt` sidecar from the assignment
  /// folder, or returns null if the folder doesn't have one. Used to refresh
  /// form validation rules on the delta-skip path, where a full shapefile
  /// re-download would be wasteful but the sidecar may have been updated
  /// since the last import.
  Future<Uint8List?> fetchFieldRequirementsSidecar(String assignmentId);

  /// Uploads [files] to /firecheck/{assignmentId}/ on Drive.
  ///
  /// Files whose name already exists in the assignment folder are
  /// overwritten (last upload wins). Conflict safety is handled at the
  /// database layer (see submit_attribution_with_conflict_check), not
  /// by per-user file separation. Photos should use unique filenames
  /// so they accumulate rather than overwriting each other.
  ///
  /// [enumeratorId] is retained on the signature for audit metadata but
  /// is no longer part of the Drive path.
  ///
  /// Returns the folder's human-readable path and its full Drive URL.
  Future<({String folderPath, String folderUrl})> uploadAssignmentFiles({
    required String enumeratorId,
    required String assignmentId,
    required List<({String filename, Uint8List bytes})> files,
  });
}
