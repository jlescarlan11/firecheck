import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firecheck/core/sync/worker/connectivity_listener.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('triggers on transition to non-none connectivity', () async {
    final controller = StreamController<List<ConnectivityResult>>();
    var triggers = 0;
    final listener =
        ConnectivityListener(stream: controller.stream, onConnect: () async => triggers++)
          ..start();

    controller.add([ConnectivityResult.none]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(triggers, 0);

    controller.add([ConnectivityResult.wifi]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(triggers, 1);

    controller.add([ConnectivityResult.mobile]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(triggers, 2);

    controller.add([ConnectivityResult.none]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(triggers, 2);

    await listener.dispose();
    await controller.close();
  });
}
