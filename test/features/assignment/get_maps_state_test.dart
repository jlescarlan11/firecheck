import 'package:firecheck/features/assignment/domain/get_maps_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GetMapsState.overallProgress', () {
    test('Idle is 0', () {
      expect(const Idle().overallProgress, 0.0);
    });
    test('FetchingFeatures is 0.05', () {
      expect(const FetchingFeatures().overallProgress, 0.05);
    });
    test('DownloadingTiles at 0% is 0.05', () {
      expect(
        const DownloadingTiles(downloadedBytes: 0, totalBytes: 100)
            .overallProgress,
        closeTo(0.05, 0.001),
      );
    });
    test('DownloadingTiles at 50% is 0.525', () {
      expect(
        const DownloadingTiles(downloadedBytes: 50, totalBytes: 100)
            .overallProgress,
        closeTo(0.525, 0.001),
      );
    });
    test('DownloadingTiles with zero total returns 0.05 (safe for division)',
        () {
      expect(
        const DownloadingTiles(downloadedBytes: 0, totalBytes: 0)
            .overallProgress,
        closeTo(0.05, 0.001),
      );
    });
    test('Ready is 1.0', () {
      expect(
        const Ready(featureCount: 10, totalBytes: 1000).overallProgress,
        1.0,
      );
    });
    test('Cancelled is 0', () {
      expect(const Cancelled().overallProgress, 0.0);
    });
  });
}
