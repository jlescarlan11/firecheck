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

class FetchingFeatures extends GetMapsState {
  const FetchingFeatures();
  @override
  double get overallProgress => 0.05;
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
  double get overallProgress => 0.05 + 0.95 * tileProgress;
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
