import 'package:flutter/widgets.dart';

class SyncLifecycleListener {
  SyncLifecycleListener({required Future<void> Function() onResume})
      : _onResume = onResume;

  final Future<void> Function() _onResume;
  AppLifecycleListener? _listener;

  void start() {
    _listener = AppLifecycleListener(
      onResume: () async => _onResume(),
    );
  }

  void dispose() {
    _listener?.dispose();
    _listener = null;
  }
}
