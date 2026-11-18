import 'dart:isolate';
import 'dart:ui';

import 'package:firecheck/core/drive/drive_upload_process_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

Future<void> _resolveInChild((String, SendPort) request) async {
  request.$2
      .send(await resolveDriveUploadProcessIdentity(registryName: request.$1));
}

void main() {
  test('overlapping resolvers share the VM process identity', () async {
    final name = 'process-identity-test-${const Uuid().v4()}';
    addTearDown(() => IsolateNameServer.removePortNameMapping(name));
    final identities = await Future.wait([
      resolveDriveUploadProcessIdentity(registryName: name),
      resolveDriveUploadProcessIdentity(registryName: name),
    ]);
    expect(identities.first, isNotNull);
    expect(identities.last, identities.first);
  });

  test('a separate isolate resolves the same process UUID', () async {
    final name = 'process-identity-test-${const Uuid().v4()}';
    addTearDown(() => IsolateNameServer.removePortNameMapping(name));
    final parent = await resolveDriveUploadProcessIdentity(registryName: name);
    final reply = ReceivePort();
    addTearDown(reply.close);
    final child = await Isolate.spawn(_resolveInChild, (name, reply.sendPort));
    addTearDown(() => child.kill(priority: Isolate.immediate));
    expect(await reply.first.timeout(const Duration(seconds: 3)), parent);
  });

  test('a terminated registry owner fails closed without replacing its name',
      () async {
    final name = 'process-identity-test-${const Uuid().v4()}';
    final deadOwner = ReceivePort();
    final original = deadOwner.sendPort;
    expect(IsolateNameServer.registerPortWithName(original, name), isTrue);
    deadOwner.close();
    addTearDown(() => IsolateNameServer.removePortNameMapping(name));
    expect(
      await resolveDriveUploadProcessIdentity(
        registryName: name,
        responseTimeout: const Duration(milliseconds: 10),
      ),
      isNull,
    );
    expect(IsolateNameServer.lookupPortByName(name), original);
  });

  test('an invalid registry response supplies no claim identity', () async {
    final name = 'process-identity-test-${const Uuid().v4()}';
    final owner = ReceivePort()
      ..listen((message) => (message as SendPort).send(42));
    expect(
      IsolateNameServer.registerPortWithName(owner.sendPort, name),
      isTrue,
    );
    addTearDown(() {
      owner.close();
      IsolateNameServer.removePortNameMapping(name);
    });
    expect(await resolveDriveUploadProcessIdentity(registryName: name), isNull);
  });
}
