import 'package:firecheck/core/photos/camera_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FakeCameraService returns scripted path and counts calls', () async {
    final c = FakeCameraService(scriptedPath: '/tmp/photo.jpg');
    expect(await c.capturePhoto(), '/tmp/photo.jpg');
    expect(await c.capturePhoto(), '/tmp/photo.jpg');
    expect(c.callCount, 2);
  });

  test('FakeCameraService with no scripted path returns null (user cancel)',
      () async {
    final c = FakeCameraService();
    expect(await c.capturePhoto(), isNull);
  });

  test('FakeCameraService exposes a scripted lost-data result', () async {
    final camera = FakeCameraService(scriptedLostPath: '/tmp/lost.jpg');

    expect(await camera.recoverLostPhoto(), '/tmp/lost.jpg');
    expect(camera.recoveryCallCount, 1);
  });
}
