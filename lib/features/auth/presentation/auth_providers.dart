import 'package:firecheck/core/security/secure_storage.dart';
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Single source of auth truth. Emits null when signed out, Session when signed in.
final supabaseAuthStateProvider = StreamProvider<Session?>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange
      .map((event) => event.session);
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
