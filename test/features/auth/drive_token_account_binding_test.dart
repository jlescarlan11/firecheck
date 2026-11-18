import 'dart:async';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/security/secure_storage.dart';
import 'package:firecheck/features/auth/data/cached_token_source.dart';
import 'package:firecheck/features/auth/data/caching_google_auth_repository.dart';
import 'package:firecheck/features/auth/data/fake_google_auth_repository.dart';
import 'package:firecheck/features/auth/data/google_access_token_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Auth extends Mock implements GoTrueClient {}

class _User extends Mock implements User {}

class _Session extends Mock implements Session {}

class _AccountRepo extends FakeGoogleAuthRepository {
  String actor = 'B';
  String? token;
  @override
  Future<String> getEnumeratorId() async => actor;
  @override
  Future<String> getAccessToken() async => token ?? 'token-$actor';
}

class _HeldStorage extends InMemorySecureStorage {
  Future<void> Function(String key)? beforeRead;
  Future<void> Function(String key, String value)? beforeWrite;
  @override
  Future<String?> read(String key) async {
    await beforeRead?.call(key);
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    await beforeWrite?.call(key, value);
    return super.write(key, value);
  }
}

void main() {
  late InMemorySecureStorage storage;
  late SecureStorageGoogleAccessTokenCache cache;
  setUp(() async {
    storage = InMemorySecureStorage();
    cache = SecureStorageGoogleAccessTokenCache(storage);
    // An old unowned cache entry must never be assigned to the live actor.
    await storage.write('google_access_token', 'token-A');
    await storage.write(
      'google_access_token_expires_at',
      DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String(),
    );
  });
  test('foreground B ignores unowned A credential and acquires B token',
      () async {
    final repo =
        CachingGoogleAuthRepository(inner: _AccountRepo(), cache: cache);
    expect(await repo.getAccessToken(), 'token-B');
  });
  test('WorkManager B rejects unowned A credential', () async {
    final auth = _Auth();
    final user = _User();
    when(() => user.id).thenReturn('B');
    when(() => auth.currentUser).thenReturn(user);
    when(() => auth.currentSession).thenReturn(_Session());
    final source = CachedTokenSource(auth: auth, cache: cache);
    await expectLater(source.getAccessToken(), throwsA(isA<AuthFailure>()));
  });
  test('atomic owned records never combine a delayed A token with B ownership',
      () async {
    final held = _HeldStorage();
    final boundCache = SecureStorageGoogleAccessTokenCache(held);
    final entered = Completer<void>();
    final release = Completer<void>();
    held.beforeWrite = (key, value) async {
      if (value.contains('token-A')) {
        entered.complete();
        await release.future;
      }
    };
    final a = boundCache.save(
      'token-A',
      DateTime.now().toUtc().add(const Duration(hours: 1)),
      accountId: 'A',
    );
    await entered.future;
    await boundCache.save(
      'token-B',
      DateTime.now().toUtc().add(const Duration(hours: 1)),
      accountId: 'B',
    );
    release.complete();
    await a;
    expect(await boundCache.read(accountId: 'B'), isNull);
    expect(await boundCache.read(accountId: 'A'), 'token-A');
  });

  for (final background in [false, true]) {
    test(
        '${background ? "background" : "foreground"} cached read rejects a mid-await account switch',
        () async {
      final held = _HeldStorage();
      final boundCache = SecureStorageGoogleAccessTokenCache(held);
      await boundCache.save(
        'token-A',
        DateTime.now().toUtc().add(const Duration(hours: 1)),
        accountId: 'A',
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      held.beforeRead = (key) async {
        entered.complete();
        await release.future;
      };
      final inner = _AccountRepo()..actor = 'A';
      var active = 'A';
      final auth = _Auth();
      final user = _User();
      when(() => user.id).thenAnswer((_) => active);
      when(() => auth.currentUser).thenReturn(user);
      when(() => auth.currentSession).thenReturn(_Session());
      final running = background
          ? CachedTokenSource(auth: auth, cache: boundCache).getAccessToken()
          : CachingGoogleAuthRepository(inner: inner, cache: boundCache)
              .getAccessToken();
      final rejected = expectLater(running, throwsA(isA<AuthFailure>()));
      await entered.future;
      active = 'B';
      inner.actor = 'B';
      release.complete();
      await rejected;
    });
  }

  test(
      'signout and relogin of the same account clears old credentials and binds a fresh token',
      () async {
    final inner = _AccountRepo()..actor = 'A';
    final repo = CachingGoogleAuthRepository(inner: inner, cache: cache);
    await cache.save(
      'old-token-A',
      DateTime.now().toUtc().add(const Duration(hours: 1)),
      accountId: 'A',
    );
    await repo.signOut();
    expect(await cache.read(accountId: 'A'), isNull);
    await repo.signIn();
    inner.token = 'fresh-token-A';
    expect(await repo.getAccessToken(), 'fresh-token-A');
    expect(await cache.read(accountId: 'A'), 'fresh-token-A');
    expect(await cache.read(accountId: 'B'), isNull);
  });
}
