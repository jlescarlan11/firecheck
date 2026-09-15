// test/features/auth/caching_google_auth_repository_test.dart
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/security/secure_storage.dart';
import 'package:firecheck/features/auth/data/caching_google_auth_repository.dart';
import 'package:firecheck/features/auth/data/fake_google_auth_repository.dart';
import 'package:firecheck/features/auth/data/google_access_token_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SecureStorageGoogleAccessTokenCache cache;
  late FakeGoogleAuthRepository inner;
  late CachingGoogleAuthRepository repo;

  setUp(() {
    cache = SecureStorageGoogleAccessTokenCache(InMemorySecureStorage());
    inner = FakeGoogleAuthRepository();
    repo = CachingGoogleAuthRepository(inner: inner, cache: cache);
  });

  test('getAccessToken persists the inner token to the cache', () async {
    expect(await cache.read(), isNull);
    final token = await repo.getAccessToken();
    expect(token, 'fake-access-token');
    expect(await cache.read(), 'fake-access-token');
  });

  test('valid cached token avoids invoking Google account restoration',
      () async {
    final countingInner = _CountingTokenRepo();
    final cachedRepo = CachingGoogleAuthRepository(
      inner: countingInner,
      cache: cache,
    );
    await cache.save(
      'restored-token',
      DateTime.now().toUtc().add(const Duration(hours: 1)),
    );

    expect(await cachedRepo.getAccessToken(), 'restored-token');
    expect(countingInner.tokenRequests, 0);
  });

  test('signOut clears the cached token', () async {
    await cache.save(
      'leftover-tok',
      DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    await repo.signOut();
    expect(await cache.read(), isNull);
  });

  test('a saved token cannot be used after the app session signs out',
      () async {
    await cache.save(
        'old-token', DateTime.now().toUtc().add(const Duration(hours: 1)),);
    await inner.signOut();
    await expectLater(repo.getAccessToken(), throwsA(isA<AuthFailure>()));
    expect(await cache.read(), isNull);
  });

  test('a new login clears tokens belonging to the previous account', () async {
    await cache.save(
        'old-token', DateTime.now().toUtc().add(const Duration(hours: 1)),);
    await repo.signIn();
    expect(await cache.read(), isNull);
  });

  test('expired cache gets a fresh access token', () async {
    await cache.save('expired-token',
        DateTime.now().toUtc().subtract(const Duration(hours: 1)),);
    expect(await repo.getAccessToken(), 'fake-access-token');
    expect(await cache.read(), 'fake-access-token');
  });

  test('non-cached methods pass through to the inner repo', () async {
    expect(await repo.isSignedIn(), isTrue);
    expect(
      await repo.getEnumeratorId(),
      '00000000-0000-0000-0000-000000000001',
    );
    expect(await repo.requestDriveUploadScope(), isTrue);

    await repo.signOut();
    expect(await repo.isSignedIn(), isFalse);
    await repo.signIn();
    expect(await repo.isSignedIn(), isTrue);
  });

  test('empty access token from inner is not written to cache', () async {
    final emptyInner = _EmptyTokenRepo();
    final r = CachingGoogleAuthRepository(inner: emptyInner, cache: cache);
    expect(await r.getAccessToken(), isEmpty);
    expect(await cache.read(), isNull);
  });
}

class _EmptyTokenRepo extends FakeGoogleAuthRepository {
  @override
  Future<String> getAccessToken() async => '';
}

class _CountingTokenRepo extends FakeGoogleAuthRepository {
  int tokenRequests = 0;

  @override
  Future<String> getAccessToken() async {
    tokenRequests += 1;
    return super.getAccessToken();
  }
}
