// lib/core/auth/current_user_provider.dart
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Returns the Supabase user id, or null when not signed in.
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(supabaseAuthStateProvider).valueOrNull?.user.id;
});
