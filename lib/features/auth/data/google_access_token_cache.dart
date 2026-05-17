// lib/features/auth/data/google_access_token_cache.dart
import 'package:firecheck/core/security/secure_storage.dart';

/// Persists the most recent Google OAuth access token so background isolates
/// (e.g. the periodic Drive upload WorkManager job) can re-use it without
/// re-running the interactive Google sign-in flow.
abstract class GoogleAccessTokenCache {
  Future<void> save(String accessToken, DateTime expiresAt);
  Future<String?> read();
  Future<void> clear();
}

class SecureStorageGoogleAccessTokenCache implements GoogleAccessTokenCache {
  SecureStorageGoogleAccessTokenCache(this._storage);

  final SecureStorage _storage;

  static const _tokenKey = 'google_access_token';
  static const _expiresKey = 'google_access_token_expires_at';

  // Treat tokens within this window of expiry as already expired so callers
  // get a fresh one before requests start failing mid-flight.
  static const _skew = Duration(minutes: 1);

  @override
  Future<void> save(String accessToken, DateTime expiresAt) async {
    await _storage.write(_tokenKey, accessToken);
    await _storage.write(_expiresKey, expiresAt.toUtc().toIso8601String());
  }

  @override
  Future<String?> read() async {
    final token = await _storage.read(_tokenKey);
    final expiresStr = await _storage.read(_expiresKey);
    if (token == null || expiresStr == null) return null;
    final expiresAt = DateTime.tryParse(expiresStr);
    if (expiresAt == null) return null;
    if (DateTime.now().toUtc().isAfter(expiresAt.subtract(_skew))) return null;
    return token;
  }

  @override
  Future<void> clear() async {
    await _storage.delete(_tokenKey);
    await _storage.delete(_expiresKey);
  }
}
