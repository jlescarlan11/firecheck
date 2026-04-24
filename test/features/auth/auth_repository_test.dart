import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/security/secure_storage.dart';
import 'package:firecheck/features/auth/data/auth_repository.dart';
import 'package:firecheck/features/auth/domain/auth_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockUser extends Mock implements User {}

class _MockSession extends Mock implements Session {}

class _MockAuthResponse extends Mock implements AuthResponse {}

void main() {
  late _MockSupabaseClient client;
  late _MockGoTrueClient auth;
  late InMemorySecureStorage storage;
  late AuthRepository repo;

  setUp(() {
    client = _MockSupabaseClient();
    auth = _MockGoTrueClient();
    storage = InMemorySecureStorage();
    when(() => client.auth).thenReturn(auth);
    repo = AuthRepository(client: client, storage: storage);
  });

  group('login', () {
    test('persists refresh token and returns Authenticated', () async {
      final user = _MockUser();
      when(() => user.id).thenReturn('user-1');
      when(() => user.email).thenReturn('j@example.com');

      final session = _MockSession();
      when(() => session.refreshToken).thenReturn('refresh-xyz');
      when(() => session.user).thenReturn(user);

      final resp = _MockAuthResponse();
      when(() => resp.user).thenReturn(user);
      when(() => resp.session).thenReturn(session);

      when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => resp);

      final state = await repo.login('j@example.com', 'password123');

      expect(state, isA<Authenticated>());
      expect((state as Authenticated).userId, 'user-1');
      expect(await storage.read('refresh_token'), 'refresh-xyz');
    });

    test('returns AuthFailure on bad credentials', () async {
      when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(const AuthException('invalid'));

      expect(
        () => repo.login('bad', 'bad'),
        throwsA(isA<AuthFailure>()),
      );
    });
  });

  group('logout', () {
    test('signs out and clears refresh token', () async {
      await storage.write('refresh_token', 'stale');
      when(() => auth.signOut()).thenAnswer((_) async => {});

      await repo.logout();

      expect(await storage.read('refresh_token'), isNull);
      verify(() => auth.signOut()).called(1);
    });
  });

  group('restoreSession', () {
    test('returns Unauthenticated when no refresh token stored', () async {
      expect(await repo.restoreSession(), isA<Unauthenticated>());
    });

    test('returns Authenticated on valid refresh', () async {
      await storage.write('refresh_token', 'refresh-xyz');

      final user = _MockUser();
      when(() => user.id).thenReturn('user-1');
      when(() => user.email).thenReturn('j@example.com');

      final session = _MockSession();
      when(() => session.refreshToken).thenReturn('refresh-new');
      when(() => session.user).thenReturn(user);

      final resp = _MockAuthResponse();
      when(() => resp.session).thenReturn(session);
      when(() => resp.user).thenReturn(user);

      when(() => auth.setSession('refresh-xyz'))
          .thenAnswer((_) async => resp);

      final state = await repo.restoreSession();

      expect(state, isA<Authenticated>());
      expect(await storage.read('refresh_token'), 'refresh-new');
    });

    test('clears token and returns Unauthenticated on refresh failure',
        () async {
      await storage.write('refresh_token', 'refresh-expired');
      when(() => auth.setSession(any())).thenThrow(const AuthException('x'));

      final state = await repo.restoreSession();

      expect(state, isA<Unauthenticated>());
      expect(await storage.read('refresh_token'), isNull);
    });
  });
}
