import 'package:firecheck/core/photos/pending_photo_capture_store.dart';
import 'package:firecheck/core/security/secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pending capture survives store recreation and clears', () async {
    final storage = InMemorySecureStorage();
    final first = PendingPhotoCaptureStore(storage);
    await first.save(
      const PendingPhotoCapture(
        submissionId: 'submission-1',
        featureId: 'feature-1',
      ),
    );

    final restored = await PendingPhotoCaptureStore(storage).read();
    expect(restored?.submissionId, 'submission-1');
    expect(restored?.featureId, 'feature-1');

    await first.clear();
    expect(await first.read(), isNull);
  });
}
