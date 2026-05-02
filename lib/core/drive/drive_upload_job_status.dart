class DriveUploadJobStatus {
  DriveUploadJobStatus._();

  static const pending = 'pending';
  static const uploading = 'uploading';
  static const completed = 'completed';
  static const failed = 'failed';
  static const dead = 'dead';

  static const typePhoto = 'photo';
  static const typeShapefile = 'shapefile';
}
