// lib/features/auth/data/caching_google_auth_repository.dart
import 'package:firecheck/features/auth/data/google_access_token_cache.dart';
import 'package:firecheck/features/auth/data/google_auth_repository.dart';

/// Decorator that persists every fresh access token to a shared
/// [GoogleAccessTokenCache] so background isolates (which cannot run the
/// interactive sign-in flow) can re-use it via a [GoogleTokenSource] that
/// reads the same cache.
///
/// Wraps any [GoogleAuthRepository] and adds two behaviours:
///   * `getAccessToken` writes the returned token to the cache before
///     returning it to the caller.
///   * `signOut` clears the cache after the inner sign-out completes, so a
///     background isolate cannot keep using a token that no longer maps to
///     an active Supabase session.
///
/// All other methods pass through unchanged.
class CachingGoogleAuthRepository implements GoogleAuthRepository {
  CachingGoogleAuthRepository({
    required GoogleAuthRepository inner,
    required GoogleAccessTokenCache cache,
    Duration ttl = const Duration(minutes: 55),
  })  : _inner = inner,
        _cache = cache,
        _ttl = ttl;

  // Google OAuth access tokens default to a 1-hour lifetime. google_sign_in
  // does not expose the expiry, so default to a conservative 55-minute TTL.
  final GoogleAuthRepository _inner;
  final GoogleAccessTokenCache _cache;
  final Duration _ttl;

  @override
  Future<bool> isSignedIn() => _inner.isSignedIn();

  @override
  Future<String> getEnumeratorId() => _inner.getEnumeratorId();

  @override
  Future<void> signIn() => _inner.signIn();

  @override
  Future<bool> requestDriveUploadScope() =>
      _inner.requestDriveUploadScope();

  @override
  Future<void> signOut() async {
    await _inner.signOut();
    await _cache.clear();
  }

  @override
  Future<String> getAccessToken() async {
    final token = await _inner.getAccessToken();
    if (token.isNotEmpty) {
      await _cache.save(token, DateTime.now().toUtc().add(_ttl));
    }
    return token;
  }
}
