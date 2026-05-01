// lib/core/drive/drive_api.dart
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';

abstract interface class DriveApi {
  /// Lists /firecheck/inbox/ subfolders readable by the signed-in user.
  Future<List<DriveAssignment>> listAssignments();

  /// Sum of all shapefile component sizes in bytes from Drive file metadata.
  Future<int> getTotalSize(String assignmentId);

  /// Streams download events for all shapefile components in the folder.
  Stream<DriveDownloadEvent> downloadShapefiles(String assignmentId);
}
