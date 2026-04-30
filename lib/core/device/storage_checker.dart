// lib/core/device/storage_checker.dart
import 'package:disk_space/disk_space.dart';

abstract class StorageChecker {
  Future<int> getAvailableBytes();
}

class FakeStorageChecker implements StorageChecker {
  const FakeStorageChecker({required this.availableBytes});
  final int availableBytes;

  @override
  Future<int> getAvailableBytes() async => availableBytes;
}

class DeviceStorageChecker implements StorageChecker {
  const DeviceStorageChecker();

  @override
  Future<int> getAvailableBytes() async {
    final freeMb = await DiskSpace.getFreeDiskSpace;
    if (freeMb == null) return 0;
    return (freeMb * 1024 * 1024).round();
  }
}
