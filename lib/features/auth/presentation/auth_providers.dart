import 'package:firecheck/core/security/secure_storage.dart';
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Single source of auth truth. Emits null when signed out, Session when signed in.
/// Yields current session immediately so the router doesn't hang on AsyncLoading.
final supabaseAuthStateProvider = StreamProvider<Session?>((ref) async* {
  final client = Supabase.instance.client;
  yield client.auth.currentSession;
  yield* client.auth.onAuthStateChange.map((e) => e.session);
});

/// Overridden in main.dart with SupabaseGoogleAuthRepository.
final googleAuthRepositoryProvider = Provider<GoogleAuthRepository>((ref) {
  throw UnimplementedError(
    'Override googleAuthRepositoryProvider in main.dart',
  );
});

final secureStorageProvider = Provider<SecureStorage>((_) {
  return FlutterSecureStorageAdapter();
});
