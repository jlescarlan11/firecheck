import 'package:firecheck/features/map/presentation/camera_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('equality is by requestId only', () {
    const a = CameraTarget(lat: 10, lng: 123, zoom: 17, requestId: 1);
    const b = CameraTarget(lat: 99, lng: 99, zoom: 5, requestId: 1);
    const c = CameraTarget(lat: 10, lng: 123, zoom: 17, requestId: 2);

    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(c));
  });
}
