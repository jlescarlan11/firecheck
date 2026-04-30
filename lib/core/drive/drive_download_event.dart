import 'dart:typed_data';

sealed class DriveDownloadEvent {
  const DriveDownloadEvent();
}

class DriveDownloadProgress extends DriveDownloadEvent {
  const DriveDownloadProgress({required this.downloaded, required this.total});
  final int downloaded;
  final int total;
}

class DriveDownloadComplete extends DriveDownloadEvent {
  const DriveDownloadComplete(this.bytes);
  final Uint8List bytes;
}
