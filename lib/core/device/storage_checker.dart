import 'package:disk_space/disk_space.dart';
import 'package:flutter/foundation.dart';

abstract interface class StorageChecker {
  Future<int> getAvailableBytes();
}

@immutable
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
    return (freeMb * 1024 * 1024).truncate().clamp(0, double.maxFinite.toInt());
  }
}
