// lib/features/auth/data/google_auth_repository.dart
abstract interface class GoogleAuthRepository {
  Future<bool> isSignedIn();
  Future<void> signIn();
  Future<void> signOut();

  /// Returns the local-part of the signed-in Gmail address (e.g. 'jlescarlan11').
  Future<String> getEnumeratorId();
}
