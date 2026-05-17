// test/features/auth/cached_google_auth_repository_test.dart
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/security/secure_storage.dart';
import 'package:firecheck/features/auth/data/cached_google_auth_repository.dart';
import 'package:firecheck/features/auth/data/google_access_token_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockSession extends Mock implements Session {}

class _MockUser extends Mock implements User {}

void main() {
  late _MockGoTrueClient auth;
  late SecureStorageGoogleAccessTokenCache cache;

  setUp(() {
    auth = _MockGoTrueClient();
    cache = SecureStorageGoogleAccessTokenCache(InMemorySecureStorage());
  });

  test('isSignedIn reflects Supabase session presence', () async {
    when(() => auth.currentSession).thenReturn(_MockSession());
    final repo = CachedGoogleAuthRepository(auth: auth, cache: cache);
    expect(await repo.isSignedIn(), isTrue);

    when(() => auth.currentSession).thenReturn(null);
    expect(await repo.isSignedIn(), isFalse);
  });

  test('getEnumeratorId returns Supabase user id', () async {
    final user = _MockUser();
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.id).thenReturn('uuid-123');
    final repo = CachedGoogleAuthRepository(auth: auth, cache: cache);
    expect(await repo.getEnumeratorId(), 'uuid-123');
  });

  test('getEnumeratorId throws AuthFailure when no Supabase user', () async {
    when(() => auth.currentUser).thenReturn(null);
    final repo = CachedGoogleAuthRepository(auth: auth, cache: cache);
    expect(repo.getEnumeratorId(), throwsA(isA<AuthFailure>()));
  });

  test('getAccessToken returns cached token when valid', () async {
    await cache.save(
      'cached-tok',
      DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    final repo = CachedGoogleAuthRepository(auth: auth, cache: cache);
    expect(await repo.getAccessToken(), 'cached-tok');
  });

  test('getAccessToken throws AuthFailure when cache is empty', () async {
    final repo = CachedGoogleAuthRepository(auth: auth, cache: cache);
    expect(repo.getAccessToken(), throwsA(isA<AuthFailure>()));
  });

  test('getAccessToken throws AuthFailure when cached token is stale',
      () async {
    await cache.save(
      'expired-tok',
      DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
    );
    final repo = CachedGoogleAuthRepository(auth: auth, cache: cache);
    expect(repo.getAccessToken(), throwsA(isA<AuthFailure>()));
  });

  test('mutating methods throw UnsupportedError', () async {
    final repo = CachedGoogleAuthRepository(auth: auth, cache: cache);
    expect(() => repo.signIn(), throwsA(isA<UnsupportedError>()));
    expect(() => repo.signOut(), throwsA(isA<UnsupportedError>()));
    expect(
      () => repo.requestDriveUploadScope(),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
