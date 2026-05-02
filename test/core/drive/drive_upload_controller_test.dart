import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firecheck/core/drive/drive_upload_controller.dart';
import 'package:firecheck/core/drive/drive_upload_preferences.dart';
import 'package:firecheck/core/security/secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('triggerNow calls onDrain', () async {
    var drainCalled = 0;
    final prefs = DriveUploadPreferences(InMemorySecureStorage());
    final ctrl = DriveUploadController(
      onDrain: () async => drainCalled++,
      preferences: prefs,
    );

    await ctrl.triggerNow();
    expect(drainCalled, 1);
  });

  test('Wi-Fi connectivity event triggers drain when auto-upload is on',
      () async {
    final controller = StreamController<List<ConnectivityResult>>();
    var drainCalled = 0;
    final storage = InMemorySecureStorage();
    final prefs = DriveUploadPreferences(storage);
    await prefs.setAutoUploadEnabled(enabled: true);

    final ctrl = DriveUploadController(
      onDrain: () async => drainCalled++,
      preferences: prefs,
      connectivityStream: controller.stream,
    );
    await ctrl.start();

    controller.add([ConnectivityResult.wifi]);
    await Future.delayed(Duration.zero);

    expect(drainCalled, greaterThanOrEqualTo(1));
    await ctrl.stop();
    await controller.close();
  });

  test('mobile connectivity does not trigger drain', () async {
    final controller = StreamController<List<ConnectivityResult>>();
    var drainCalled = 0;
    final prefs = DriveUploadPreferences(InMemorySecureStorage());
    await prefs.setAutoUploadEnabled(enabled: true);

    final ctrl = DriveUploadController(
      onDrain: () async => drainCalled++,
      preferences: prefs,
      connectivityStream: controller.stream,
    );
    await ctrl.start();

    controller.add([ConnectivityResult.mobile]);
    await Future.delayed(Duration.zero);

    expect(drainCalled, 0);
    await ctrl.stop();
    await controller.close();
  });

  test('Wi-Fi event does not trigger drain when auto-upload is off', () async {
    final streamCtrl = StreamController<List<ConnectivityResult>>();
    var drainCalled = 0;
    final prefs = DriveUploadPreferences(InMemorySecureStorage());
    // auto-upload default is false

    final ctrl = DriveUploadController(
      onDrain: () async => drainCalled++,
      preferences: prefs,
      connectivityStream: streamCtrl.stream,
    );
    await ctrl.start();

    streamCtrl.add([ConnectivityResult.wifi]);
    await Future.delayed(Duration.zero);

    expect(drainCalled, 0);
    await ctrl.stop();
    await streamCtrl.close();
  });
}
