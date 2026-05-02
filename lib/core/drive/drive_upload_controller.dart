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
            Connectivity()
                .onConnectivityChanged
                .map((r) => <ConnectivityResult>[r]);

  final Future<void> Function() _onDrain;
  final DriveUploadPreferences _preferences;
  final Stream<List<ConnectivityResult>> _connectivityStream;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  Future<void> start() async {
    _sub = _connectivityStream.listen((results) async {
      final isWifi = results.any((r) => r == ConnectivityResult.wifi);
      if (!isWifi) return;
      final autoEnabled = await _preferences.isAutoUploadEnabled();
      if (autoEnabled) await _onDrain();
    });
  }

  Future<void> triggerNow() => _onDrain();

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}
