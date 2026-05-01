// test/features/assignment/get_maps_state_test.dart
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/assignment/domain/get_maps_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('overallProgress', () {
    test('Idle → 0', () => expect(const Idle().overallProgress, 0));

    test('DiscoveringAssignments → 0.02', () {
      expect(const DiscoveringAssignments().overallProgress, 0.02);
    });

    test('PickingAssignment → 0.02', () {
      expect(
        PickingAssignment(assignments: [], selectedId: '').overallProgress,
        0.02,
      );
    });

    test('InsufficientStorage → 0.02', () {
      expect(
        InsufficientStorage(requiredBytes: 100, availableBytes: 10)
            .overallProgress,
        0.02,
      );
    });

    test('DownloadingShapefiles mid-way → between 0.02 and 0.30', () {
      final s = DownloadingShapefiles(downloaded: 500, total: 1000);
      expect(s.overallProgress, closeTo(0.02 + 0.28 * 0.5, 1e-9));
    });

    test('DownloadingShapefiles zero total → 0.02', () {
      expect(
        DownloadingShapefiles(downloaded: 0, total: 0).overallProgress,
        0.02,
      );
    });

    test('ImportingShapefiles → 0.35', () {
      expect(const ImportingShapefiles().overallProgress, 0.35);
    });

    test('DownloadingTiles mid-way → between 0.35 and 1.0', () {
      final s = DownloadingTiles(downloadedBytes: 1, totalBytes: 2);
      expect(s.overallProgress, closeTo(0.35 + 0.65 * 0.5, 1e-9));
    });

    test('Ready → 1', () {
      expect(Ready(featureCount: 0, totalBytes: 0).overallProgress, 1);
    });

    test('Cancelled → 0', () => expect(const Cancelled().overallProgress, 0));

    test('GetMapsError → 0', () {
      expect(
        GetMapsError(const NetworkFailure()).overallProgress,
        0,
      );
    });
  });
}
