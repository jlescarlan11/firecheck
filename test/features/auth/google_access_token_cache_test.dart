// test/features/auth/google_access_token_cache_test.dart
import 'package:firecheck/core/security/secure_storage.dart';
import 'package:firecheck/features/auth/data/google_access_token_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemorySecureStorage storage;
  late SecureStorageGoogleAccessTokenCache cache;

  setUp(() {
    storage = InMemorySecureStorage();
    cache = SecureStorageGoogleAccessTokenCache(storage);
  });

  test('save then read returns the token while it is still valid', () async {
    await cache.save(
      'tok-1',
      DateTime.now().toUtc().add(const Duration(hours: 1)),
      accountId: 'cache-owner',
    );
    expect(await cache.read(accountId: 'cache-owner'), 'tok-1');
  });

  test('read returns null when token has expired', () async {
    await cache.save(
      'tok-1',
      DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
      accountId: 'cache-owner',
    );
    expect(await cache.read(accountId: 'cache-owner'), isNull);
  });

  test('read returns null when token is within the safety skew window',
      () async {
    // Skew is 1 minute; expiry 30s in the future is treated as expired.
    await cache.save(
      'tok-1',
      DateTime.now().toUtc().add(const Duration(seconds: 30)),
      accountId: 'cache-owner',
    );
    expect(await cache.read(accountId: 'cache-owner'), isNull);
  });

  test('read returns null when nothing was saved', () async {
    expect(await cache.read(accountId: 'cache-owner'), isNull);
  });

  test('clear removes the token', () async {
    await cache.save(
      'tok-1',
      DateTime.now().toUtc().add(const Duration(hours: 1)),
      accountId: 'cache-owner',
    );
    await cache.clear();
    expect(await cache.read(accountId: 'cache-owner'), isNull);
  });

  test('read returns null when stored expiry timestamp is malformed', () async {
    await storage.write('google_access_token', 'tok-1');
    await storage.write('google_access_token_expires_at', 'not-a-date');
    expect(await cache.read(accountId: 'cache-owner'), isNull);
  });
}
