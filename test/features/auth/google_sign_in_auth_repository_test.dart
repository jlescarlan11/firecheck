// test/features/auth/google_sign_in_auth_repository_test.dart
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/auth/data/google_sign_in_auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockSession extends Mock implements Session {}

class _MockUser extends Mock implements User {}

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

class _MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

class _MockAuthorizationClient extends Mock
    implements GoogleSignInAuthorizationClient {}

class _MockClientAuthorization extends Mock
    implements GoogleSignInClientAuthorization {}

void main() {
  late _MockGoTrueClient auth;
  late _MockGoogleSignIn gsi;

  setUp(() {
    auth = _MockGoTrueClient();
    gsi = _MockGoogleSignIn();
    when(() => gsi.authenticationEvents).thenAnswer(
      (_) => const Stream<GoogleSignInAuthenticationEvent>.empty(),
    );
  });

  GoogleSignInAuthRepository buildRepo() => GoogleSignInAuthRepository(
        auth: auth,
        googleSignIn: gsi,
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
    test('returns access token from lightweight-restored account', () async {
      final account = _MockGoogleSignInAccount();
      final authzClient = _MockAuthorizationClient();
      final authz = _MockClientAuthorization();

      when(() => gsi.attemptLightweightAuthentication())
          .thenAnswer((_) => Future.value(account));
      when(() => account.authorizationClient).thenReturn(authzClient);
      when(() => authzClient.authorizationForScopes(any()))
          .thenAnswer((_) async => authz);
      when(() => authz.accessToken).thenReturn('fresh-token');

      expect(await buildRepo().getAccessToken(), 'fresh-token');
    });

    test('falls back to interactive authorizeScopes when silent returns null',
        () async {
      final account = _MockGoogleSignInAccount();
      final authzClient = _MockAuthorizationClient();
      final authz = _MockClientAuthorization();

      when(() => gsi.attemptLightweightAuthentication())
          .thenAnswer((_) => Future.value(account));
      when(() => account.authorizationClient).thenReturn(authzClient);
      when(() => authzClient.authorizationForScopes(any()))
          .thenAnswer((_) async => null);
      when(() => authzClient.authorizeScopes(any()))
          .thenAnswer((_) async => authz);
      when(() => authz.accessToken).thenReturn('interactive-token');

      expect(await buildRepo().getAccessToken(), 'interactive-token');
      verify(() => authzClient.authorizeScopes(any())).called(1);
    });

    test('throws AuthFailure when no account can be restored', () async {
      when(() => gsi.attemptLightweightAuthentication())
          .thenAnswer((_) => Future.value(null));
      expect(buildRepo().getAccessToken(), throwsA(isA<AuthFailure>()));
    });
  });
}
