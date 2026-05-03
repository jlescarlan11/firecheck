// lib/features/auth/data/supabase_google_auth_repository.dart
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class SupabaseGoogleAuthRepository implements GoogleAuthRepository {
  SupabaseGoogleAuthRepository({required GoTrueClient auth}) : _auth = auth;

  final GoTrueClient _auth;

  @override
  Future<bool> isSignedIn() async => _auth.currentSession != null;

  @override
  Future<void> signIn() async {
    await _auth.signInWithOAuth(
      OAuthProvider.google,
      scopes: 'email profile ${GoogleAuthRepository.driveFileScope}',
      redirectTo: 'io.supabase.firecheck://login-callback',
    );
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<String> getEnumeratorId() async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthFailure('Not signed in');
    return user.email!.split('@').first;
  }

  @override
  Future<bool> requestDriveUploadScope() async => true;

  @override
  Future<String> getAccessToken() async {
    var session = _auth.currentSession;
    if (session?.providerToken == null) {
      final response = await _auth.refreshSession();
      session = response.session;
    }
    final token = session?.providerToken;
    if (token == null) {
      throw const AuthFailure('Google provider token unavailable');
    }
    return token;
  }
}
