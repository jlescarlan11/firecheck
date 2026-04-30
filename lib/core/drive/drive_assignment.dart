import 'package:flutter/foundation.dart';

@immutable
class DriveAssignment {
  const DriveAssignment({
    required this.assignmentId,
    required this.inputZipFileId,
    required this.inputZipModifiedTime,
    required this.driveFolderId,
    this.alreadyDownloaded = false,
  });

  final String assignmentId;
  final String inputZipFileId;
  final String inputZipModifiedTime;
  final String driveFolderId;
  final bool alreadyDownloaded;

  DriveAssignment copyWith({bool? alreadyDownloaded}) => DriveAssignment(
        assignmentId: assignmentId,
        inputZipFileId: inputZipFileId,
        inputZipModifiedTime: inputZipModifiedTime,
        driveFolderId: driveFolderId,
        alreadyDownloaded: alreadyDownloaded ?? this.alreadyDownloaded,
      );

  @override
  bool operator ==(Object other) =>
      other is DriveAssignment &&
      other.assignmentId == assignmentId &&
      other.inputZipFileId == inputZipFileId &&
      other.inputZipModifiedTime == inputZipModifiedTime &&
      other.driveFolderId == driveFolderId &&
      other.alreadyDownloaded == alreadyDownloaded;

  @override
  int get hashCode => Object.hash(
      assignmentId, inputZipFileId, inputZipModifiedTime,
      driveFolderId, alreadyDownloaded);
}
