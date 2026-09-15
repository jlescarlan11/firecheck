// test/features/auth/google_sign_in_auth_repository_test.dart
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/auth/data/google_sign_in_auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class _MockPlatform extends Mock implements GoogleSignInPlatform {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockSession extends Mock implements Session {}

class _MockUser extends Mock implements User {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

class _MockAuthorizationClient extends Mock
    implements GoogleSignInAuthorizationClient {}

void main() {
  late _MockGoTrueClient auth;
  late _MockGoogleSignIn gsi;
  late _MockPlatform platform;
  late _MockUser user;

  setUpAll(() {
    registerFallbackValue(
      const ClientAuthorizationTokensForScopesParameters(
        request: AuthorizationRequestDetails(
          scopes: [],
          userId: null,
          email: null,
          promptIfUnauthorized: false,
        ),
      ),
    );
  });

  setUp(() {
    auth = _MockGoTrueClient();
    gsi = _MockGoogleSignIn();
    platform = _MockPlatform();
    user = _MockUser();
    when(() => auth.currentSession).thenReturn(_MockSession());
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.id).thenReturn('supabase-user');
    when(() => user.identities).thenReturn([
      const UserIdentity(
        id: 'google-user',
        userId: 'supabase-user',
        identityId: 'identity-uuid',
        provider: 'google',
        createdAt: null,
        lastSignInAt: null,
        identityData: {'email': 'selected@example.com'},
      ),
    ]);
    when(() => gsi.authenticationEvents).thenAnswer(
      (_) => const Stream<GoogleSignInAuthenticationEvent>.empty(),
    );
  });

  GoogleSignInAuthRepository buildRepo() => GoogleSignInAuthRepository(
        auth: auth,
        googleSignIn: gsi,
        authorizationPlatform: platform,
      );

  group('isSignedIn', () {
    test('reflects Supabase session presence', () async {
      when(() => auth.currentSession).thenReturn(_MockSession());
      expect(await buildRepo().isSignedIn(), isTrue);

      when(() => auth.currentSession).thenReturn(null);
      expect(await buildRepo().isSignedIn(), isFalse);
    });
  });

  group('getEnumeratorId', () {
    test('returns Supabase user UUID', () async {
      final user = _MockUser();
      when(() => auth.currentUser).thenReturn(user);
      when(() => user.id).thenReturn('user-uuid');
      expect(await buildRepo().getEnumeratorId(), 'user-uuid');
    });

    test('throws AuthFailure when not signed in', () async {
      when(() => auth.currentUser).thenReturn(null);
      expect(buildRepo().getEnumeratorId(), throwsA(isA<AuthFailure>()));
    });
  });

  group('signOut', () {
    test('clears Google Sign-In and Supabase session', () async {
      when(() => gsi.signOut()).thenAnswer((_) async {});
      when(() => auth.signOut()).thenAnswer((_) async {});

      await buildRepo().signOut();

      verify(() => gsi.signOut()).called(1);
      verify(() => auth.signOut()).called(1);
    });
  });

  group('getAccessToken', () {
    test('after restart refreshes for saved Google identity without sign-in UI',
        () async {
      when(() => platform.clientAuthorizationTokensForScopes(any())).thenAnswer(
        (_) async =>
            const ClientAuthorizationTokenData(accessToken: 'fresh-token'),
      );
      expect(await buildRepo().getAccessToken(), 'fresh-token');
      final params = verify(
        () => platform.clientAuthorizationTokensForScopes(captureAny()),
      ).captured.single as ClientAuthorizationTokensForScopesParameters;
      expect(params.request.userId, 'google-user');
      expect(params.request.email, 'selected@example.com');
      expect(params.request.promptIfUnauthorized, isFalse);
      expect(
        params.request.scopes,
        contains('https://www.googleapis.com/auth/drive.readonly'),
      );
      verifyNever(() => gsi.attemptLightweightAuthentication());
      verifyNever(() => gsi.authenticate());
    });

    test('revoked consent asks for reconnection without opening a picker',
        () async {
      when(() => platform.clientAuthorizationTokensForScopes(any()))
          .thenAnswer((_) async => null);
      await expectLater(
        buildRepo().getAccessToken(),
        throwsA(isA<AuthFailure>()),
      );
      final params = verify(
        () => platform.clientAuthorizationTokensForScopes(captureAny()),
      ).captured.single as ClientAuthorizationTokensForScopesParameters;
      expect(params.request.promptIfUnauthorized, isFalse);
      verifyNever(() => gsi.attemptLightweightAuthentication());
      verifyNever(() => gsi.authenticate());
    });

    test('signed-out user cannot request Drive tokens', () async {
      when(() => auth.currentSession).thenReturn(null);
      await expectLater(
        buildRepo().getAccessToken(),
        throwsA(isA<AuthFailure>()),
      );
      verifyNever(() => platform.clientAuthorizationTokensForScopes(any()));
    });

    test(
        'missing linked identity never falls back to a different device account',
        () async {
      when(() => user.identities).thenReturn([]);
      await expectLater(
        buildRepo().getAccessToken(),
        throwsA(isA<AuthFailure>()),
      );
      verifyNever(() => platform.clientAuthorizationTokensForScopes(any()));
    });

    test('sign-out while refreshing discards the returned token', () async {
      when(() => platform.clientAuthorizationTokensForScopes(any()))
          .thenAnswer((_) async {
        when(() => auth.currentSession).thenReturn(null);
        return const ClientAuthorizationTokenData(
          accessToken: 'old-user-token',
        );
      });
      await expectLater(
        buildRepo().getAccessToken(),
        throwsA(isA<AuthFailure>()),
      );
    });
  });

  test('gateway login never requests Google Drive permission', () async {
    final account = _MockGoogleSignInAccount();
    when(() => gsi.authenticate()).thenAnswer((_) async => account);
    when(() => account.authentication)
        .thenReturn(const GoogleSignInAuthentication(idToken: 'id-token'));
    when(() => auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: 'id-token')).thenAnswer((_) async => AuthResponse());
    final repo = GoogleSignInAuthRepository(
        auth: auth, googleSignIn: gsi, requireDriveConsent: false);
    await repo.signIn();
    verifyNever(() => account.authorizationClient);
    verify(() => gsi.authenticate()).called(1);
  });
  group('signIn', () {
    test('obtains Drive consent before publishing the FireCheck session',
        () async {
      final account = _MockGoogleSignInAccount();
      final client = _MockAuthorizationClient();
      final calls = <String>[];
      when(() => gsi.authenticate()).thenAnswer((_) async => account);
      when(() => account.authentication)
          .thenReturn(const GoogleSignInAuthentication(idToken: 'id-token'));
      when(() => account.authorizationClient).thenReturn(client);
      when(() => client.authorizationForScopes(any()))
          .thenAnswer((_) async => null);
      when(() => client.authorizeScopes(any())).thenAnswer((_) async {
        calls.add('consent');
        return const GoogleSignInClientAuthorization(
          accessToken: 'drive-token',
        );
      });
      when(
        () => auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: 'id-token',
        ),
      ).thenAnswer((_) async {
        calls.add('session');
        return AuthResponse();
      });
      await buildRepo().signIn();
      expect(calls, ['consent', 'session']);
      verify(() => gsi.authenticate()).called(1);
    });

    test('denied Drive consent does not publish a signed-in session', () async {
      final account = _MockGoogleSignInAccount();
      final client = _MockAuthorizationClient();
      when(() => gsi.authenticate()).thenAnswer((_) async => account);
      when(() => account.authentication)
          .thenReturn(const GoogleSignInAuthentication(idToken: 'id-token'));
      when(() => account.authorizationClient).thenReturn(client);
      when(() => client.authorizationForScopes(any()))
          .thenAnswer((_) async => null);
      when(() => client.authorizeScopes(any()))
          .thenThrow(const AuthFailure('Denied'));
      await expectLater(buildRepo().signIn(), throwsA(isA<AuthFailure>()));
      verifyNever(
        () => auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: 'id-token',
        ),
      );
    });

    test('existing Drive consent is reused during login', () async {
      final account = _MockGoogleSignInAccount();
      final client = _MockAuthorizationClient();
      when(() => gsi.authenticate()).thenAnswer((_) async => account);
      when(() => account.authentication)
          .thenReturn(const GoogleSignInAuthentication(idToken: 'id-token'));
      when(() => account.authorizationClient).thenReturn(client);
      when(() => client.authorizationForScopes(any())).thenAnswer(
        (_) async =>
            const GoogleSignInClientAuthorization(accessToken: 'drive-token'),
      );
      when(
        () => auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: 'id-token',
        ),
      ).thenAnswer((_) async => AuthResponse());
      await buildRepo().signIn();
      verifyNever(() => client.authorizeScopes(any()));
    });
  });
}
