// test/features/auth/google_auth_notifier_test.dart
import 'package:firecheck/features/auth/data/fake_google_auth_repository.dart';
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:firecheck/features/auth/presentation/google_auth_providers.dart';
import 'package:flutter_test/flutter_test.dart';

class _ThrowingAuthRepository implements GoogleAuthRepository {
  @override
  Future<bool> isSignedIn() => Future.error(Exception('storage failure'));
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<String> getEnumeratorId() async => 'test-enumerator';
}

void main() {
  test('transitions loading → signedIn when repo is signed-in', () async {
    final notifier = GoogleAuthNotifier(FakeGoogleAuthRepository(startSignedIn: true));
    expect(notifier.state, GoogleAuthState.loading);
    await Future.microtask(() {});
    expect(notifier.state, GoogleAuthState.signedIn);
  });

  test('transitions loading → signedOut when repo is not signed-in', () async {
    final notifier = GoogleAuthNotifier(FakeGoogleAuthRepository(startSignedIn: false));
    expect(notifier.state, GoogleAuthState.loading);
    await Future.microtask(() {});
    expect(notifier.state, GoogleAuthState.signedOut);
  });

  test('signIn transitions to signedIn', () async {
    final notifier = GoogleAuthNotifier(FakeGoogleAuthRepository(startSignedIn: false));
    await Future.microtask(() {});
    await notifier.signIn();
    expect(notifier.state, GoogleAuthState.signedIn);
  });

  test('signOut transitions to signedOut', () async {
    final notifier = GoogleAuthNotifier(FakeGoogleAuthRepository(startSignedIn: true));
    await Future.microtask(() {});
    await notifier.signOut();
    expect(notifier.state, GoogleAuthState.signedOut);
  });

  test('_init error falls back to signedOut', () async {
    final notifier = GoogleAuthNotifier(_ThrowingAuthRepository());
    await Future.microtask(() {});
    expect(notifier.state, GoogleAuthState.signedOut);
  });
}
