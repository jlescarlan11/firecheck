import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/security/secure_storage.dart';
import 'package:firecheck/features/auth/data/auth_repository.dart';
import 'package:firecheck/features/auth/domain/auth_state.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

/// A [SecureStorage] that always returns null (no stored token).
class _NullStorage implements SecureStorage {
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> delete(String key) async {}
  @override
  Future<void> clear() async {}
}

/// A fake [AuthRepository] whose [restoreSession] returns [Unauthenticated]
/// immediately, so [AuthStateNotifier._bootstrap] does not overwrite the
/// initial state we set in [_StubAuthNotifier].
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
      : super(
          client: SupabaseClient('http://localhost', 'fake-key'),
          storage: _NullStorage(),
        );

  @override
  Future<AuthState> restoreSession() async => const Unauthenticated();
}

/// Subclasses [AuthStateNotifier] to set an explicit initial [AuthState]
/// before [_bootstrap] can overwrite it.
class _StubAuthNotifier extends AuthStateNotifier {
  _StubAuthNotifier(AuthState initial) : super(_FakeAuthRepository()) {
    state = initial;
  }
}

void main() {
  test('returns userId for Authenticated', () {
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => _StubAuthNotifier(
            const Authenticated(userId: 'u-123', email: 'a@b.c'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(currentUserIdProvider), 'u-123');
  });

  test('returns null for Unauthenticated', () {
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => _StubAuthNotifier(const Unauthenticated()),
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(currentUserIdProvider), isNull);
  });

  test('returns null for AuthChecking', () {
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => _StubAuthNotifier(const AuthChecking()),
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(currentUserIdProvider), isNull);
  });
}
