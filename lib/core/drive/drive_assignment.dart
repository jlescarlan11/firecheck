import 'package:flutter/foundation.dart';

@immutable
class DriveAssignment {
  const DriveAssignment({
    required this.assignmentId,
    required this.localAssignmentId,
    required this.inputZipModifiedTime,
    required this.driveFolderId,
    this.alreadyDownloaded = false,
    this.downloadedAssignmentId,
    this.displayName,
  });

  /// Drive folder name — used as the cache key for file lookups.
  /// May be a human-readable string (e.g. "cebu") or a UUID.
  final String assignmentId;
  final String? displayName;

  /// Always a UUID. Derived from the folder name: if the folder name is
  /// already a UUID it equals [assignmentId]; otherwise it is a stable
  /// v5 UUID seeded from the folder name so the same folder always maps
  /// to the same local id across reinstalls.
  final String localAssignmentId;

  final String inputZipModifiedTime;
  final String driveFolderId;

  /// Whether the original download matches the current source version.
  /// This is an import optimization, not local availability or sync freshness.
  final bool alreadyDownloaded;
  final String? downloadedAssignmentId;

  DriveAssignment copyWith(
          {bool? alreadyDownloaded, String? downloadedAssignmentId}) =>
      DriveAssignment(
        assignmentId: assignmentId,
        displayName: displayName,
        localAssignmentId: localAssignmentId,
        inputZipModifiedTime: inputZipModifiedTime,
        driveFolderId: driveFolderId,
        alreadyDownloaded: alreadyDownloaded ?? this.alreadyDownloaded,
        downloadedAssignmentId:
            downloadedAssignmentId ?? this.downloadedAssignmentId,
      );

  @override
  bool operator ==(Object other) =>
      other is DriveAssignment &&
      other.assignmentId == assignmentId &&
      other.localAssignmentId == localAssignmentId &&
      other.inputZipModifiedTime == inputZipModifiedTime &&
      other.driveFolderId == driveFolderId &&
      other.displayName == displayName &&
      other.alreadyDownloaded == alreadyDownloaded &&
      other.downloadedAssignmentId == downloadedAssignmentId;

  @override
  int get hashCode => Object.hash(
      assignmentId,
      localAssignmentId,
      inputZipModifiedTime,
      driveFolderId,
      alreadyDownloaded,
      displayName,
      downloadedAssignmentId);
}
