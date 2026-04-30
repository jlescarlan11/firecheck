// lib/core/drive/drive_api.dart
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';

abstract class DriveApi {
  /// Lists /firecheck/inbox/ subfolders readable by the signed-in user.
  Future<List<DriveAssignment>> listAssignments();

  /// Size of input.zip in bytes from Drive file metadata.
  Future<int> getInputZipSize(String assignmentId);

  /// Streams download events for input.zip.
  Stream<DriveDownloadEvent> downloadInputZip(String assignmentId);
}
