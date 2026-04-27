import 'package:firecheck/features/auth/domain/auth_state.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Returns the current Supabase user id, or null when not authenticated.
/// Replaces the Phase 4a `'admin'` placeholder at submission call sites.
final currentUserIdProvider = Provider<String?>((ref) {
  final auth = ref.watch(authStateProvider);
  return auth is Authenticated ? auth.userId : null;
});
