import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firecheck/core/sync/worker/realtime_sync_controller.dart';
import 'package:flutter/widgets.dart';

/// Glue between platform inputs (connectivity, app lifecycle) and the
/// [RealtimeSyncController]'s state-machine entry points.
///
/// The existing `ConnectivityListener` / `SyncLifecycleListener` fire only on
/// the "good" transition (connect / resume). The realtime state machine
/// also needs the inverse transitions (disconnect / background) so we
/// can drop the channel correctly. Rather than widen the existing
/// listeners (and affect the push-side sync controller), this bridge
/// owns its own stream subscriptions and translates them into controller
/// method calls.
class RealtimeWiring {
  RealtimeWiring({
    required RealtimeSyncController controller,
    Stream<List<ConnectivityResult>>? connectivityStream,
  })  : _controller = controller,
        _connectivityStream = connectivityStream ??
            Connectivity()
                .onConnectivityChanged
                .map((r) => <ConnectivityResult>[r]);

  final RealtimeSyncController _controller;
  final Stream<List<ConnectivityResult>> _connectivityStream;

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  AppLifecycleListener? _lifecycle;

  void start() {
    _connSub = _connectivityStream.listen((results) async {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) {
        await _controller.onNetworkRestored();
      } else {
        await _controller.onNetworkLost();
      }
    });

    _lifecycle = AppLifecycleListener(
      onResume: () async => _controller.onAppResumed(),
      onPause: _controller.onAppBackgrounded,
      onHide: _controller.onAppBackgrounded,
    );
  }

  Future<void> dispose() async {
    await _connSub?.cancel();
    _lifecycle?.dispose();
    _lifecycle = null;
  }
}
