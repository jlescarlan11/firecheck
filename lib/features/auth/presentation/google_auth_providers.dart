// lib/features/auth/presentation/google_auth_providers.dart
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum GoogleAuthState { loading, signedIn, signedOut }

class GoogleAuthNotifier extends StateNotifier<GoogleAuthState> {
  GoogleAuthNotifier(this._repo) : super(GoogleAuthState.loading) {
    _init();
  }

  final GoogleAuthRepository _repo;

  Future<void> _init() async {
    try {
      final signed = await _repo.isSignedIn();
      if (!mounted) return;
      state = signed ? GoogleAuthState.signedIn : GoogleAuthState.signedOut;
    } catch (_) {
      if (!mounted) return;
      state = GoogleAuthState.signedOut;
    }
  }

  Future<void> signIn() async {
    try {
      await _repo.signIn();
      if (!mounted) return;
      state = GoogleAuthState.signedIn;
    } catch (e) {
      if (!mounted) return;
      state = GoogleAuthState.signedOut;
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _repo.signOut();
    if (!mounted) return;
    state = GoogleAuthState.signedOut;
  }
}

/// Overridden in main.dart with GoogleSignInAuthRepository.
final googleAuthRepositoryProvider = Provider<GoogleAuthRepository>((ref) {
  throw UnimplementedError('Override googleAuthRepositoryProvider in main.dart');
});

final googleAuthNotifierProvider =
    StateNotifierProvider<GoogleAuthNotifier, GoogleAuthState>((ref) {
  return GoogleAuthNotifier(ref.watch(googleAuthRepositoryProvider));
});
