// lib/features/auth/data/cached_token_source.dart
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/auth/data/google_access_token_cache.dart';
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

/// Read-only token source for background isolates that cannot launch the
/// interactive Google sign-in flow. Returns the most recent access token
/// the foreground app persisted to [GoogleAccessTokenCache]. If the cache
/// is empty or stale, [getAccessToken] throws [AuthFailure] so callers
/// can defer the work until the foreground app refreshes the token.
class CachedTokenSource implements GoogleTokenSource {
  CachedTokenSource({
    required GoTrueClient auth,
    required GoogleAccessTokenCache cache,
  })  : _auth = auth,
        _cache = cache;

  final GoTrueClient _auth;
  final GoogleAccessTokenCache _cache;

  @override
  Future<bool> isSignedIn() async => _auth.currentSession != null;

  @override
  Future<String> getEnumeratorId() async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthFailure('Not signed in');
    return user.id;
  }

  @override
  Future<String> getAccessToken() async {
    final token = await _cache.read();
    if (token == null) {
      throw const AuthFailure(
        'No cached Google access token. Refresh from the foreground app.',
      );
    }
    return token;
  }
}
