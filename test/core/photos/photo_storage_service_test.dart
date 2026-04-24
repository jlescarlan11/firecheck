import 'package:firecheck/core/photos/photo_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('InMemoryPhotoStorage hands out distinct paths per call', () async {
    final s = InMemoryPhotoStorage();
    final a = await s.reserveDestPath(submissionId: 'sub1');
    final b = await s.reserveDestPath(submissionId: 'sub1');
    expect(a, isNot(b));
    expect(a, contains('/sub1/'));
  });

  test('deleteFile records the deletion', () async {
    final s = InMemoryPhotoStorage();
    await s.deleteFile('/tmp/foo.jpg');
    expect(s.deleted, contains('/tmp/foo.jpg'));
  });
}
