// test/features/auth/cached_token_source_test.dart
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/security/secure_storage.dart';
import 'package:firecheck/features/auth/data/cached_token_source.dart';
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
    final source = CachedTokenSource(auth: auth, cache: cache);
    expect(await source.isSignedIn(), isTrue);

    when(() => auth.currentSession).thenReturn(null);
    expect(await source.isSignedIn(), isFalse);
  });

  test('getEnumeratorId returns Supabase user id', () async {
    final user = _MockUser();
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.id).thenReturn('uuid-123');
    final source = CachedTokenSource(auth: auth, cache: cache);
    expect(await source.getEnumeratorId(), 'uuid-123');
  });

  test('getEnumeratorId throws AuthFailure when no Supabase user', () async {
    when(() => auth.currentUser).thenReturn(null);
    final source = CachedTokenSource(auth: auth, cache: cache);
    expect(source.getEnumeratorId(), throwsA(isA<AuthFailure>()));
  });

  test('getAccessToken returns cached token when valid', () async {
    await cache.save(
      'cached-tok',
      DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
    final source = CachedTokenSource(auth: auth, cache: cache);
    expect(await source.getAccessToken(), 'cached-tok');
  });

  test('getAccessToken throws AuthFailure when cache is empty', () async {
    final source = CachedTokenSource(auth: auth, cache: cache);
    expect(source.getAccessToken(), throwsA(isA<AuthFailure>()));
  });

  test('getAccessToken throws AuthFailure when cached token is stale',
      () async {
    await cache.save(
      'expired-tok',
      DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
    );
    final source = CachedTokenSource(auth: auth, cache: cache);
    expect(source.getAccessToken(), throwsA(isA<AuthFailure>()));
  });
}
