class DriveUploadJobStatus {
  DriveUploadJobStatus._();

  static const pending = 'pending';
  static const uploading = 'uploading';
  static const completed = 'completed';
  static const failed = 'failed';
  static const dead = 'dead';
}

class DriveFileType {
  DriveFileType._();

  static const photo = 'photo';
  static const shapefile = 'shapefile';
}
