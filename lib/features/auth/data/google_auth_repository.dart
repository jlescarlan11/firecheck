// lib/features/auth/data/google_auth_repository.dart
abstract interface class GoogleAuthRepository {
  static const driveFileScope =
      'https://www.googleapis.com/auth/drive.file';

  // Needed to list supervisor-shared assignment folders.
  static const driveReadonlyScope =
      'https://www.googleapis.com/auth/drive.readonly';

  Future<bool> isSignedIn();
  Future<void> signIn();
  Future<void> signOut();

  /// Returns the Supabase user UUID for the currently signed-in user.
  /// Throws [AuthFailure] if no session is active.
  Future<String> getEnumeratorId();

  /// Requests the drive.file OAuth scope. Returns true if granted.
  Future<bool> requestDriveUploadScope();

  /// Returns a valid Google OAuth access token. Refreshes the Supabase
  /// session first if providerToken is absent.
  Future<String> getAccessToken();
}
