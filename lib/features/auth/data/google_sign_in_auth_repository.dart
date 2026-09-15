// lib/features/auth/data/google_sign_in_auth_repository.dart
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

/// Auth repository backed by the native `google_sign_in` SDK.
///
/// Unlike Supabase OAuth (which discards the Google access token after the
/// Supabase session is refreshed), `google_sign_in` manages Google tokens
/// natively and can refresh the access token silently. The Supabase session
/// is established by exchanging the Google id_token via
/// `GoTrueClient.signInWithIdToken`.
class GoogleSignInAuthRepository implements GoogleAuthRepository {
  GoogleSignInAuthRepository({
    required GoTrueClient auth,
    required GoogleSignIn googleSignIn,
    GoogleSignInPlatform? authorizationPlatform,
    this.requireDriveConsent = true,
  })  : _auth = auth,
        _googleSignIn = googleSignIn,
        _authorizationPlatform = authorizationPlatform;

  final bool requireDriveConsent;
  final GoTrueClient _auth;
  final GoogleSignIn _googleSignIn;
  final GoogleSignInPlatform? _authorizationPlatform;

  static const List<String> _driveScopes = <String>[
    GoogleTokenSource.driveReadonlyScope,
    GoogleTokenSource.driveFileScope,
  ];

  Future<void> dispose() async {}

  @override
  Future<bool> isSignedIn() async => _auth.currentSession != null;

  @override
  Future<void> signIn() async {
    final account = await _googleSignIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthFailure('Google sign-in did not return an id_token');
    }
    // Finish Drive consent before publishing the app session. Navigation and
    // background work can start as soon as signInWithIdToken emits that session.
    if (requireDriveConsent) {
      final client = account.authorizationClient;
      final authorization = await client.authorizationForScopes(_driveScopes) ??
          await client.authorizeScopes(_driveScopes);
      if (authorization.accessToken.isEmpty) {
        throw const AuthFailure('Google Drive access was not granted.');
      }
    }
    await _auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
  }

  @override
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } finally {
      await _auth.signOut();
    }
  }

  @override
  Future<String> getEnumeratorId() async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthFailure('Not signed in');
    return user.id;
  }

  @override
  Future<bool> requestDriveUploadScope() async {
    return (await _authorizeDrive(prompt: true)).isNotEmpty;
  }

  @override
  Future<String> getAccessToken() async {
    return _authorizeDrive(prompt: false);
  }

  Future<String> _authorizeDrive({required bool prompt}) async {
    final user = _auth.currentUser;
    if (_auth.currentSession == null || user == null) {
      throw const AuthFailure('Sign in to FireCheck to access Google Drive.');
    }
    // Use the linked provider identity, never editable profile metadata or an
    // unscoped authorization client that could select another device account.
    final identities = user.identities
        ?.where((identity) => identity.provider == 'google')
        .toList();
    if (identities == null || identities.length != 1) {
      throw const AuthFailure(
        'Please sign out and sign in with Google to connect Drive.',
      );
    }
    final identity = identities.single;
    final email = identity.identityData?['email'];
    if (identity.id.isEmpty || email is! String || email.isEmpty) {
      throw const AuthFailure(
        'Please sign out and sign in with Google to connect Drive.',
      );
    }
    // The SDK's authorization API refreshes access tokens for this account
    // without requesting a new ID token through Android Credential Manager.
    final tokens =
        await (_authorizationPlatform ?? GoogleSignInPlatform.instance)
            .clientAuthorizationTokensForScopes(
      ClientAuthorizationTokensForScopesParameters(
        request: AuthorizationRequestDetails(
          scopes: _driveScopes,
          userId: identity.id,
          email: email,
          promptIfUnauthorized: prompt,
        ),
      ),
    );
    if (tokens == null || tokens.accessToken.isEmpty) {
      throw const AuthFailure(
        'Google Drive access needs to be reconnected. Please sign out and sign in again to allow Drive access.',
      );
    }
    if (_auth.currentUser?.id != user.id || _auth.currentSession == null) {
      throw const AuthFailure('Your account changed. Please try again.');
    }
    return tokens.accessToken;
  }
}
