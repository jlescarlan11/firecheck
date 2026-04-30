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
}
