// test/core/device/storage_checker_test.dart
import 'package:firecheck/core/device/storage_checker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FakeStorageChecker returns configured bytes', () async {
    final checker = FakeStorageChecker(availableBytes: 50 * 1024 * 1024);
    expect(await checker.getAvailableBytes(), 50 * 1024 * 1024);
  });
}
