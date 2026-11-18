import 'dart:convert';

import 'package:firecheck/core/security/secure_storage.dart';

/// An atomic account-bound credential for foreground and background Drive work.
abstract class GoogleAccessTokenCache {
  Future<void> save(
    String accessToken,
    DateTime expiresAt, {
    required String accountId,
  });
  Future<String?> read({required String accountId});
  Future<void> clear();
}

class SecureStorageGoogleAccessTokenCache implements GoogleAccessTokenCache {
  SecureStorageGoogleAccessTokenCache(this._storage);
  final SecureStorage _storage;
  static const _recordKey = 'google_access_token_record';
  static const _skew = Duration(minutes: 1);

  @override
  Future<void> save(
    String accessToken,
    DateTime expiresAt, {
    required String accountId,
  }) async {
    if (accountId.isEmpty) throw ArgumentError.value(accountId, 'accountId');
    // One storage write prevents owner/token/expiry pairs from different
    // asynchronous sign-ins being combined into a credential for another user.
    await _storage.write(
      _recordKey,
      jsonEncode({
        'account_id': accountId,
        'access_token': accessToken,
        'expires_at': expiresAt.toUtc().toIso8601String(),
      }),
    );
  }

  @override
  Future<String?> read({required String accountId}) async {
    if (accountId.isEmpty) return null;
    final raw = await _storage.read(_recordKey);
    if (raw == null) {
      return null; // Unowned legacy keys are deliberately ignored.
    }
    try {
      final record = jsonDecode(raw);
      if (record is! Map<String, dynamic> ||
          record['account_id'] != accountId) {
        return null;
      }
      final token = record['access_token'];
      final expiry = record['expires_at'];
      if (token is! String || token.isEmpty || expiry is! String) return null;
      final expiresAt = DateTime.tryParse(expiry);
      if (expiresAt == null ||
          DateTime.now().toUtc().isAfter(expiresAt.subtract(_skew))) {
        return null;
      }
      return token;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> clear() async {
    await _storage.delete(_recordKey);
    await _storage.delete('google_access_token');
    await _storage.delete('google_access_token_expires_at');
  }
}
