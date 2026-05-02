// test/features/auth/fake_google_auth_repository_test.dart
import 'package:firecheck/features/auth/data/fake_google_auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts signed-in when configured', () async {
    final repo = FakeGoogleAuthRepository(startSignedIn: true);
    expect(await repo.isSignedIn(), isTrue);
  });

  test('starts signed-out when configured', () async {
    final repo = FakeGoogleAuthRepository(startSignedIn: false);
    expect(await repo.isSignedIn(), isFalse);
  });

  test('signIn sets isSignedIn to true', () async {
    final repo = FakeGoogleAuthRepository(startSignedIn: false);
    await repo.signIn();
    expect(await repo.isSignedIn(), isTrue);
  });

  test('signOut sets isSignedIn to false', () async {
    final repo = FakeGoogleAuthRepository(startSignedIn: true);
    await repo.signOut();
    expect(await repo.isSignedIn(), isFalse);
  });

  test('getEnumeratorId returns test-enumerator', () async {
    final repo = FakeGoogleAuthRepository();
    expect(await repo.getEnumeratorId(), 'test-enumerator');
  });

  test('requestDriveUploadScope returns true', () async {
    final repo = FakeGoogleAuthRepository();
    expect(await repo.requestDriveUploadScope(), isTrue);
  });
}
