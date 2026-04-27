import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityListener {
  ConnectivityListener({
    required Future<void> Function() onConnect,
    Stream<List<ConnectivityResult>>? stream,
  })  : _onConnect = onConnect,
        _stream = stream ??
            Connectivity()
                .onConnectivityChanged
                .map((r) => <ConnectivityResult>[r]);

  final Future<void> Function() _onConnect;
  final Stream<List<ConnectivityResult>> _stream;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  void start() {
    _sub = _stream.listen((results) async {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) await _onConnect();
    });
  }

  Future<void> dispose() async {
    await _sub?.cancel();
  }
}
