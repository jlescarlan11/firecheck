// lib/core/sync/shapefile/export/export_failure.dart
sealed class ExportFailure {
  const ExportFailure();
}

class NoCompletedFeatures extends ExportFailure {
  const NoCompletedFeatures();
}

class WriteError extends ExportFailure {
  const WriteError(this.message);
  final String message;
}

class ShareError extends ExportFailure {
  const ShareError(this.message);
  final String message;
}
