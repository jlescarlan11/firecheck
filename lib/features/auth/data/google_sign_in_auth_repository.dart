// lib/features/auth/data/google_sign_in_auth_repository.dart
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleSignInAuthRepository implements GoogleAuthRepository {
  GoogleSignInAuthRepository({
    required GoogleSignIn googleSignIn,
    required FlutterSecureStorage secureStorage,
  })  : _googleSignIn = googleSignIn,
        _secureStorage = secureStorage;

  final GoogleSignIn _googleSignIn;
  final FlutterSecureStorage _secureStorage;

  static const _tokenKey = 'google_refresh_token';

  @override
  Future<bool> isSignedIn() async {
    final stored = await _secureStorage.read(key: _tokenKey);
    if (stored != null) return true;
    return _googleSignIn.isSignedIn();
  }

  @override
  Future<void> signIn() async {
    final account = await _googleSignIn.signIn();
    if (account == null) throw const AuthFailure('Google Sign-In cancelled');
    final auth = await account.authentication;
    final token = auth.idToken ?? auth.accessToken;
    if (token != null) {
      await _secureStorage.write(key: _tokenKey, value: token);
    }
  }

  @override
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _secureStorage.delete(key: _tokenKey);
  }

  @override
  Future<String> getEnumeratorId() async {
    final account = _googleSignIn.currentUser;
    if (account == null) throw const AuthFailure('Not signed in to Google');
    return account.email.split('@').first;
  }
}
