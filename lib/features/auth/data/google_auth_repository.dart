// lib/features/auth/data/google_auth_repository.dart

/// Narrow read-only token role.
///
/// Surface for any code that just needs the current Google OAuth access token
/// (and the Supabase identity tied to it). Background isolates that cannot
/// launch the interactive sign-in flow implement only this role.
abstract interface class GoogleTokenSource {
  /// Per-app-files scope. The app only writes to files (and folders) it
  /// created itself — sufficient because shapefile uploads now land in
  /// `firecheck/output/<assignment>/`, a subtree the app owns end-to-end.
  static const driveFileScope =
      'https://www.googleapis.com/auth/drive.file';

  // Needed to list supervisor-shared assignment folders.
  static const driveReadonlyScope =
      'https://www.googleapis.com/auth/drive.readonly';

  Future<bool> isSignedIn();

  /// Returns the Supabase user UUID for the currently signed-in user.
  /// Throws [AuthFailure] if no session is active.
  Future<String> getEnumeratorId();

  /// Returns a valid Google OAuth access token. Refreshes the Supabase
  /// session first if providerToken is absent.
  Future<String> getAccessToken();
}

/// Full auth role. Adds interactive-only operations on top of
/// [GoogleTokenSource]. The foreground app depends on this; background
/// isolates depend on the narrower role.
abstract interface class GoogleAuthRepository implements GoogleTokenSource {
  Future<void> signIn();
  Future<void> signOut();

  /// Requests the drive.file OAuth scope. Returns true if granted.
  Future<bool> requestDriveUploadScope();
}
