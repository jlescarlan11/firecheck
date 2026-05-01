import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

  static const _channel = MethodChannel('ph.gov.bfp.firecheck/device');

  @override
  Future<int> getAvailableBytes() async {
    try {
      final bytes = await _channel.invokeMethod<int>('getAvailableBytes');
      return bytes ?? 0;
    } on PlatformException {
      return 0;
    }
  }
}
