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
  const DriveDownloadComplete(this.bytes);
  final Uint8List bytes;
}
