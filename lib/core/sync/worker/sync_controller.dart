import 'dart:async';

import 'package:firecheck/core/sync/worker/connectivity_listener.dart';
import 'package:firecheck/core/sync/worker/lifecycle_listener.dart';
import 'package:firecheck/core/sync/worker/sync_worker.dart';

/// Singleton facade that wires a SyncWorker to its trigger sources
/// (connectivity, lifecycle) and exposes a public triggerNow() / start()
/// API for consumers. WorkManager periodic ticks call triggerNow on the
/// background isolate (independent SyncController instance).
class SyncController {
  SyncController(this._worker);
  final SyncWorker _worker;
  ConnectivityListener? _connectivity;
  SyncLifecycleListener? _lifecycle;

  Future<void> start() async {
    _connectivity = ConnectivityListener(onConnect: triggerNow)..start();
    _lifecycle = SyncLifecycleListener(onResume: triggerNow)..start();
    await triggerNow();
  }

  Future<void> triggerNow() => _worker.drain();

  Future<void> stop() async {
    await _connectivity?.dispose();
    _lifecycle?.dispose();
  }
}
