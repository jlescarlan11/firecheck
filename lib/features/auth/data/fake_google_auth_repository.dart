// lib/features/auth/data/fake_google_auth_repository.dart
import 'package:firecheck/features/auth/data/google_auth_repository.dart';

class FakeGoogleAuthRepository implements GoogleAuthRepository {
  FakeGoogleAuthRepository({bool startSignedIn = true})
      : _signedIn = startSignedIn;

  bool _signedIn;

  @override
  Future<bool> isSignedIn() async => _signedIn;

  @override
  Future<void> signIn() async => _signedIn = true;

  @override
  Future<void> signOut() async => _signedIn = false;

  @override
  Future<String> getEnumeratorId() async => 'test-enumerator';

  @override
  Future<bool> requestDriveUploadScope() async => true;
}
