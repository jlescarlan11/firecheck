import 'dart:typed_data';
import 'package:flutter/foundation.dart';

sealed class DriveDownloadEvent {
  const DriveDownloadEvent();
}

@immutable
class DriveDownloadProgress extends DriveDownloadEvent {
  const DriveDownloadProgress({required this.downloaded, required this.total});
  final int downloaded;
  final int total;
}

@immutable
class DriveDownloadComplete extends DriveDownloadEvent {
  const DriveDownloadComplete(this.files, this.expectedMd5s);
  final Map<String, Uint8List> files;
  // Keyed by filename (e.g. 'boundary.shp'), value is Drive's md5Checksum string.
  // Empty map if the Drive API did not return checksums for some files.
  final Map<String, String> expectedMd5s;
}
