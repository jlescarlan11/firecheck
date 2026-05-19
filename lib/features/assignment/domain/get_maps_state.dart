// lib/features/assignment/domain/get_maps_state.dart
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:flutter/foundation.dart';

sealed class GetMapsState {
  const GetMapsState();
  double get overallProgress;
}

class Idle extends GetMapsState {
  const Idle();
  @override
  double get overallProgress => 0;
}

class DiscoveringAssignments extends GetMapsState {
  const DiscoveringAssignments();
  @override
  double get overallProgress => 0.02;
}

class PickingAssignment extends GetMapsState {
  PickingAssignment({required List<DriveAssignment> assignments, required this.selectedId})
      : assignments = List.unmodifiable(assignments);
  final List<DriveAssignment> assignments;
  final String selectedId;
  @override
  double get overallProgress => 0.02;
}

/// Emitted immediately when the user taps "Download Selected", before any
/// network calls, so the UI shows a spinner within one frame.
class PreparingDownload extends GetMapsState {
  const PreparingDownload();
  @override
  double get overallProgress => 0.02;
}

class InsufficientStorage extends GetMapsState {
  const InsufficientStorage({
    required this.requiredBytes,
    required this.availableBytes,
  });
  final int requiredBytes;
  final int availableBytes;
  @override
  double get overallProgress => 0.02;
}

class DownloadingShapefiles extends GetMapsState {
  const DownloadingShapefiles({required this.downloaded, required this.total});
  final int downloaded;
  final int total;
  @override
  double get overallProgress =>
      0.02 + 0.28 * (total == 0 ? 0 : downloaded / total);
}

/// Validation is running after the download completed.
class ValidatingShapefiles extends GetMapsState {
  const ValidatingShapefiles();
  @override
  double get overallProgress => 0.30;
}

/// Validation passed with warnings. Holds the downloaded bytes so import can
/// proceed without re-downloading after the user acknowledges.
@immutable
class ShapefileWarning extends GetMapsState {
  ShapefileWarning({
    required List<String> warnings,
    required Map<String, Uint8List> pendingFiles,
    required Map<String, String> expectedMd5s,
  })  : warnings = List.unmodifiable(warnings),
        pendingFiles = Map.unmodifiable(pendingFiles),
        expectedMd5s = Map.unmodifiable(expectedMd5s);

  final List<String> warnings;
  final Map<String, Uint8List> pendingFiles;
  final Map<String, String> expectedMd5s;
  @override
  double get overallProgress => 0.30;
}

class ImportingShapefiles extends GetMapsState {
  const ImportingShapefiles();
  @override
  double get overallProgress => 0.35;
}

class DownloadingTiles extends GetMapsState {
  const DownloadingTiles({
    required this.downloadedBytes,
    required this.totalBytes,
  });
  final int downloadedBytes;
  final int totalBytes;
  double get tileProgress =>
      totalBytes == 0 ? 0 : downloadedBytes / totalBytes;
  @override
  double get overallProgress => 0.35 + 0.65 * tileProgress;
}

class Ready extends GetMapsState {
  const Ready({required this.featureCount, required this.totalBytes});
  final int featureCount;
  final int totalBytes;
  @override
  double get overallProgress => 1;
}

class Cancelled extends GetMapsState {
  const Cancelled();
  @override
  double get overallProgress => 0;
}

class GetMapsError extends GetMapsState {
  const GetMapsError(this.failure, {this.isRetryable = false});
  final Failure failure;
  // true for transient network errors (show Retry button);
  // false for validation failures (show Contact Supervisor message).
  final bool isRetryable;
  @override
  double get overallProgress => 0;
}
