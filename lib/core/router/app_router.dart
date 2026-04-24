import 'package:firecheck/features/assignment/presentation/get_maps_screen.dart';
import 'package:firecheck/features/auth/domain/auth_state.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:firecheck/features/auth/presentation/login_screen.dart';
import 'package:firecheck/features/home/presentation/home_screen.dart';
import 'package:firecheck/features/map/presentation/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(authStateProvider.notifier);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: _AuthListenable(notifier),
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      final onLogin = state.matchedLocation == '/login';

      return switch (auth) {
        AuthChecking() => null, // stay put; splash handles it
        Unauthenticated() => onLogin ? null : '/login',
        Authenticated() => onLogin ? '/' : null,
      };
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) {
          final auth = ref.watch(authStateProvider);
          if (auth is AuthChecking) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return const HomeScreen();
        },
      ),
      GoRoute(
        path: '/get-maps',
        builder: (context, state) => const GetMapsScreen(),
      ),
      GoRoute(
        path: '/map',
        builder: (context, state) => const MapScreen(),
      ),
    ],
  );
});

/// Adapts a StateNotifier into a Listenable go_router can subscribe to.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(StateNotifier<AuthState> notifier) {
    // StateNotifier.addListener returns a disposer; stash it to tear down
    // the subscription in dispose().
    _removeListener = notifier.addListener((_) => notifyListeners());
  }

  late final void Function() _removeListener;

  @override
  void dispose() {
    _removeListener();
    super.dispose();
  }
}
