import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:uuid/uuid.dart';

/// Direct-Drive runners share the Android app process and Flutter VM. A random
/// VM-lifetime identity survives foreground/headless isolate overlap and avoids
/// PID reuse. Never replace an unresponsive registration: its uploader may live.
/// If its owning isolate died, restarting the full app process restores service.
Future<String?> resolveDriveUploadProcessIdentity({
  String registryName = 'firecheck.direct-drive.process.v1',
  Duration responseTimeout = const Duration(seconds: 2),
}) async {
  ReceivePort? candidate;
  ReceivePort? reply;
  try {
    var server = IsolateNameServer.lookupPortByName(registryName);
    if (server == null) {
      candidate = ReceivePort();
      final identity = const Uuid().v4();
      if (IsolateNameServer.registerPortWithName(
        candidate.sendPort,
        registryName,
      )) {
        candidate.listen((message) {
          if (message is SendPort) message.send(identity);
        });
        // The name owns this port for the VM lifetime. Do not remove the
        // registration when an individual drain or account session finishes.
        candidate = null;
      } else {
        candidate.close();
        candidate = null;
      }
      server = IsolateNameServer.lookupPortByName(registryName);
    }
    if (server == null) return null;
    reply = ReceivePort();
    server.send(reply.sendPort);
    final response = await reply.first.timeout(responseTimeout);
    return response is String && response.isNotEmpty ? response : null;
  } on Object {
    return null;
  } finally {
    candidate?.close();
    reply?.close();
  }
}
