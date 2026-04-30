// lib/features/assignment/domain/get_maps_state.dart
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/errors/failure.dart';

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
  const GetMapsError(this.failure);
  final Failure failure;
  @override
  double get overallProgress => 0;
}
