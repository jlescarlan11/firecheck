// test/features/auth/supabase_google_auth_repository_test.dart
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/auth/data/supabase_google_auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class _MockGoTrueClient extends Mock implements GoTrueClient {}
class _MockSession extends Mock implements Session {}
class _MockUser extends Mock implements User {}
class _MockAuthResponse extends Mock implements AuthResponse {}

void main() {
  late _MockGoTrueClient auth;

  setUpAll(() {
    registerFallbackValue(OAuthProvider.google);
  });

  setUp(() {
    auth = _MockGoTrueClient();
  });

  group('isSignedIn', () {
    test('returns true when currentSession is non-null', () async {
      when(() => auth.currentSession).thenReturn(_MockSession());
      final repo = SupabaseGoogleAuthRepository(auth: auth);
      expect(await repo.isSignedIn(), isTrue);
    });

    test('returns false when currentSession is null', () async {
      when(() => auth.currentSession).thenReturn(null);
      final repo = SupabaseGoogleAuthRepository(auth: auth);
      expect(await repo.isSignedIn(), isFalse);
    });
  });

  group('getEnumeratorId', () {
    test('returns Supabase user UUID', () async {
      final user = _MockUser();
      when(() => auth.currentUser).thenReturn(user);
      when(() => user.id).thenReturn('550e8400-e29b-41d4-a716-446655440000');
      final repo = SupabaseGoogleAuthRepository(auth: auth);
      expect(
        await repo.getEnumeratorId(),
        '550e8400-e29b-41d4-a716-446655440000',
      );
    });

    test('throws AuthFailure when not signed in', () async {
      when(() => auth.currentUser).thenReturn(null);
      final repo = SupabaseGoogleAuthRepository(auth: auth);
      expect(repo.getEnumeratorId(), throwsA(isA<AuthFailure>()));
    });
  });

  group('requestDriveUploadScope', () {
    test('returns true without calling Supabase', () async {
      final repo = SupabaseGoogleAuthRepository(auth: auth);
      expect(await repo.requestDriveUploadScope(), isTrue);
      // signInWithOAuth is a supabase_flutter extension method that delegates
      // to getOAuthSignInUrl; verifying the underlying interface method is
      // sufficient to assert that no OAuth flow was started.
      verifyNever(
        () => auth.getOAuthSignInUrl(provider: any(named: 'provider')),
      );
    });
  });

  group('getAccessToken', () {
    test('returns providerToken from current session', () async {
      final session = _MockSession();
      when(() => auth.currentSession).thenReturn(session);
      when(() => session.providerToken).thenReturn('goog-token-abc');
      when(() => auth.refreshSession())
          .thenAnswer((_) async => _MockAuthResponse());
      final repo = SupabaseGoogleAuthRepository(auth: auth);
      expect(await repo.getAccessToken(), 'goog-token-abc');
      verifyNever(() => auth.refreshSession());
    });

    test('calls refreshSession when providerToken is null, returns new token',
        () async {
      final staleSession = _MockSession();
      final freshSession = _MockSession();
      final response = _MockAuthResponse();
      when(() => auth.currentSession).thenReturn(staleSession);
      when(() => staleSession.providerToken).thenReturn(null);
      when(() => auth.refreshSession()).thenAnswer((_) async => response);
      when(() => response.session).thenReturn(freshSession);
      when(() => freshSession.providerToken).thenReturn('refreshed-token');
      final repo = SupabaseGoogleAuthRepository(auth: auth);
      expect(await repo.getAccessToken(), 'refreshed-token');
      verify(() => auth.refreshSession()).called(1);
    });

    test('throws AuthFailure when providerToken is null after refresh',
        () async {
      final staleSession = _MockSession();
      final response = _MockAuthResponse();
      when(() => auth.currentSession).thenReturn(staleSession);
      when(() => staleSession.providerToken).thenReturn(null);
      when(() => auth.refreshSession()).thenAnswer((_) async => response);
      when(() => response.session).thenReturn(null);
      final repo = SupabaseGoogleAuthRepository(auth: auth);
      expect(repo.getAccessToken(), throwsA(isA<AuthFailure>()));
    });
  });
}
