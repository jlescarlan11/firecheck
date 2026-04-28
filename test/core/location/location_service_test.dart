import 'package:firecheck/core/location/location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  group('FakeLocationService', () {
    test('checkPermission returns the configured result without side effects', () async {
      final svc = FakeLocationService(
        checkPermissionResult: LocationPermission.denied,
      );
      expect(await svc.checkPermission(), LocationPermission.denied);
      // calling check should not flip request — they're independent.
      expect(await svc.requestPermission(), LocationPermission.whileInUse);
    });

    test('requestPermission returns the configured result', () async {
      final svc = FakeLocationService(
        requestPermissionResult: LocationPermission.deniedForever,
      );
      expect(await svc.requestPermission(), LocationPermission.deniedForever);
    });

    test('openAppSettings flips the recorder and returns true', () async {
      final svc = FakeLocationService();
      expect(svc.openAppSettingsCalled, isFalse);
      expect(await svc.openAppSettings(), isTrue);
      expect(svc.openAppSettingsCalled, isTrue);
    });
  });
}
