import 'package:flutter/foundation.dart';

sealed class DriveUploadState {
  const DriveUploadState();
}

@immutable
class DriveUploadIdle extends DriveUploadState {
  const DriveUploadIdle();
}

@immutable
class DriveUploadInProgress extends DriveUploadState {
  const DriveUploadInProgress(this.progress);
  final double progress; // 0.0–1.0

  @override
  bool operator ==(Object other) =>
      other is DriveUploadInProgress && other.progress == progress;
  @override
  int get hashCode => progress.hashCode;
}

@immutable
class DriveUploadSuccess extends DriveUploadState {
  const DriveUploadSuccess({
    required this.folderPath,
    required this.folderUrl,
    required this.referenceId,
    required this.confirmedAt,
  });
  final String folderPath;
  final String folderUrl;
  final String referenceId;
  final DateTime confirmedAt;

  @override
  bool operator ==(Object other) =>
      other is DriveUploadSuccess &&
      other.folderPath == folderPath &&
      other.folderUrl == folderUrl &&
      other.referenceId == referenceId &&
      other.confirmedAt == confirmedAt;
  @override
  int get hashCode =>
      Object.hash(folderPath, folderUrl, referenceId, confirmedAt);
}

@immutable
class DriveUploadFailure extends DriveUploadState {
  const DriveUploadFailure({required this.message, required this.canRetry});
  final String message;
  final bool canRetry;

  @override
  bool operator ==(Object other) =>
      other is DriveUploadFailure &&
      other.message == message &&
      other.canRetry == canRetry;
  @override
  int get hashCode => Object.hash(message, canRetry);
}
