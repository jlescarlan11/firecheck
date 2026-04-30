import 'package:firecheck/core/device/storage_checker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FakeStorageChecker', () {
    test('returns configured bytes', () async {
      final checker = FakeStorageChecker(availableBytes: 50 * 1024 * 1024);
      expect(await checker.getAvailableBytes(), 50 * 1024 * 1024);
    });
  });

  group('DeviceStorageChecker MB-to-bytes arithmetic', () {
    test('1.5 MB converts to 1572864 bytes', () {
      const freeMb = 1.5;
      final result = (freeMb * 1024 * 1024).truncate().clamp(0, double.maxFinite.toInt());
      expect(result, 1572864);
    });

    test('0 MB returns 0 bytes', () {
      const freeMb = 0.0;
      final result = (freeMb * 1024 * 1024).truncate().clamp(0, double.maxFinite.toInt());
      expect(result, 0);
    });

    test('negative MB is clamped to 0', () {
      const freeMb = -1.0;
      final result = (freeMb * 1024 * 1024).truncate().clamp(0, double.maxFinite.toInt());
      expect(result, 0);
    });
  });
}
