import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/security/secure_storage.dart';
import 'package:firecheck/features/auth/domain/auth_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class AuthRepository {
  AuthRepository({required this.client, required this.storage});
  final SupabaseClient client;
  final SecureStorage storage;

  static const _refreshTokenKey = 'refresh_token';

  Future<AuthState> login(String email, String password) async {
    try {
      final resp = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final session = resp.session;
      final user = resp.user;
      if (session == null || user == null) {
        // Failure is a sealed domain error class; repositories surface it to
        // callers the same way exceptions flow.
        // ignore: only_throw_errors
        throw const AuthFailure('Login succeeded but no session returned');
      }
      final refresh = session.refreshToken;
      if (refresh != null) {
        await storage.write(_refreshTokenKey, refresh);
      }
      return Authenticated(userId: user.id, email: user.email ?? '');
    } on AuthException catch (e) {
      // ignore: only_throw_errors
      throw AuthFailure(e.message);
    }
  }

  Future<void> logout() async {
    await client.auth.signOut();
    await storage.delete(_refreshTokenKey);
  }

  Future<AuthState> restoreSession() async {
    final refresh = await storage.read(_refreshTokenKey);
    if (refresh == null) return const Unauthenticated();
    try {
      final resp = await client.auth.setSession(refresh);
      final session = resp.session;
      final user = resp.user;
      if (session == null || user == null) {
        await storage.delete(_refreshTokenKey);
        return const Unauthenticated();
      }
      final newRefresh = session.refreshToken;
      if (newRefresh != null) {
        await storage.write(_refreshTokenKey, newRefresh);
      }
      return Authenticated(userId: user.id, email: user.email ?? '');
    } on AuthException {
      await storage.delete(_refreshTokenKey);
      return const Unauthenticated();
    }
  }
}
