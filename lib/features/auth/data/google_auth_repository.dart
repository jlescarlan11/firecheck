// lib/features/auth/data/google_auth_repository.dart
abstract interface class GoogleAuthRepository {
  static const driveFileScope =
      'https://www.googleapis.com/auth/drive.file';

  Future<bool> isSignedIn();
  Future<void> signIn();
  Future<void> signOut();

  /// Returns the local-part of the signed-in Gmail address (e.g. 'jlescarlan11').
  Future<String> getEnumeratorId();

  /// Requests the drive.file OAuth scope. Returns true if granted.
  Future<bool> requestDriveUploadScope();

  /// Returns a valid Google OAuth access token. Refreshes the Supabase
  /// session first if providerToken is absent.
  Future<String> getAccessToken();
}
