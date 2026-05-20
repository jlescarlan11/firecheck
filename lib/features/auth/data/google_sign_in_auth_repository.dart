// lib/features/auth/data/google_sign_in_auth_repository.dart
import 'dart:async';

import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:google_sign_in/google_sign_in.dart';
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
  })  : _auth = auth,
        _googleSignIn = googleSignIn {
    _eventSub = _googleSignIn.authenticationEvents.listen(
      _onAuthEvent,
      onError: (_) {},
    );
  }

  final GoTrueClient _auth;
  final GoogleSignIn _googleSignIn;
  late final StreamSubscription<GoogleSignInAuthenticationEvent> _eventSub;

  static const List<String> _driveScopes = <String>[
    GoogleTokenSource.driveReadonlyScope,
    GoogleTokenSource.driveFileScope,
  ];

  GoogleSignInAccount? _currentAccount;

  void _onAuthEvent(GoogleSignInAuthenticationEvent event) {
    if (event is GoogleSignInAuthenticationEventSignIn) {
      _currentAccount = event.user;
    } else if (event is GoogleSignInAuthenticationEventSignOut) {
      _currentAccount = null;
    }
  }

  Future<void> dispose() => _eventSub.cancel();

  @override
  Future<bool> isSignedIn() async => _auth.currentSession != null;

  @override
  Future<void> signIn() async {
    final account = await _googleSignIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthFailure('Google sign-in did not return an id_token');
    }
    await _auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
    _currentAccount = account;
  }

  @override
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
    _currentAccount = null;
  }

  @override
  Future<String> getEnumeratorId() async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthFailure('Not signed in');
    return user.id;
  }

  @override
  Future<bool> requestDriveUploadScope() async {
    final account = await _ensureAccount();
    final authz =
        await account.authorizationClient.authorizeScopes(_driveScopes);
    return authz.accessToken.isNotEmpty;
  }

  @override
  Future<String> getAccessToken() async {
    final account = await _ensureAccount();
    var authz =
        await account.authorizationClient.authorizationForScopes(_driveScopes);
    authz ??=
        await account.authorizationClient.authorizeScopes(_driveScopes);
    return authz.accessToken;
  }

  Future<GoogleSignInAccount> _ensureAccount() async {
    if (_currentAccount != null) return _currentAccount!;
    final restored = await _googleSignIn.attemptLightweightAuthentication();
    if (restored != null) {
      _currentAccount = restored;
      return restored;
    }
    throw const AuthFailure(
      'Google sign-in required. Please sign in again.',
    );
  }
}
