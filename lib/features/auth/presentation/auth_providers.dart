import 'package:firecheck/core/security/secure_storage.dart';
import 'package:firecheck/core/supabase/supabase_client_provider.dart';
import 'package:firecheck/features/auth/data/auth_repository.dart';
import 'package:firecheck/features/auth/domain/auth_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final secureStorageProvider = Provider<SecureStorage>((_) {
  return FlutterSecureStorageAdapter();
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    client: ref.watch(supabaseClientProvider),
    storage: ref.watch(secureStorageProvider),
  );
});

/// Tracks current auth state. Starts as [AuthChecking] while restoreSession
/// runs, then transitions to [Authenticated] or [Unauthenticated].
class AuthStateNotifier extends StateNotifier<AuthState> {
  AuthStateNotifier(this._repo) : super(const AuthChecking()) {
    _bootstrap();
  }

  final AuthRepository _repo;

  Future<void> _bootstrap() async {
    state = await _repo.restoreSession();
  }

  Future<void> login(String email, String password) async {
    state = await _repo.login(email, password);
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const Unauthenticated();
  }
}

final authStateProvider =
    StateNotifierProvider<AuthStateNotifier, AuthState>((ref) {
  return AuthStateNotifier(ref.watch(authRepositoryProvider));
});
