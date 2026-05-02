import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firecheck/core/drive/drive_upload_preferences.dart';

class DriveUploadController {
  DriveUploadController({
    required Future<void> Function() onDrain,
    required DriveUploadPreferences preferences,
    Stream<List<ConnectivityResult>>? connectivityStream,
  })  : _onDrain = onDrain,
        _preferences = preferences,
        _connectivityStream = connectivityStream ??
            // connectivity_plus 5.x emits a single ConnectivityResult per event.
            // Wrap in a list to match the Stream<List<ConnectivityResult>> type.
            // Remove this .map() when upgrading to 6.x (which emits natively).
            Connectivity()
                .onConnectivityChanged
                .map((r) => <ConnectivityResult>[r]);

  final Future<void> Function() _onDrain;
  final DriveUploadPreferences _preferences;
  final Stream<List<ConnectivityResult>> _connectivityStream;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  Future<void> start() async {
    await stop(); // cancel any existing subscription before creating a new one
    _sub = _connectivityStream.listen((results) async {
      final isWifi = results.any((r) => r == ConnectivityResult.wifi);
      if (!isWifi) return;
      final autoEnabled = await _preferences.isAutoUploadEnabled();
      if (autoEnabled) {
        try {
          await _onDrain();
        } on Object catch (_) {
          // drain errors are handled by the worker itself; don't kill this subscription
        }
      }
    });
  }

  Future<void> triggerNow() => _onDrain();

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}
