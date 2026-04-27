import 'package:firecheck/core/sync/worker/lifecycle_listener.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('onResume callback fires when WidgetsBinding emits resumed', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    var triggers = 0;
    final l = SyncLifecycleListener(onResume: () async => triggers++)..start();

    WidgetsBinding.instance
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(triggers, 1);

    l.dispose();
  });
}
