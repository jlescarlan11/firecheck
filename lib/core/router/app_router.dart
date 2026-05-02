import 'package:firecheck/features/assignment/presentation/assignment_closed_blocker.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_screen.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/get_maps_screen.dart';
import 'package:firecheck/features/auth/domain/auth_state.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:firecheck/features/auth/presentation/google_auth_providers.dart';
import 'package:firecheck/features/auth/presentation/login_screen.dart';
import 'package:firecheck/features/auth/presentation/sign_in_screen.dart';
import 'package:firecheck/features/home/presentation/home_screen.dart';
import 'package:firecheck/features/map/presentation/map_screen.dart';
import 'package:firecheck/features/review/presentation/review_screen.dart';
import 'package:firecheck/features/survey/building_form/presentation/submission_detail_screen.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/result/olp_result_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authNotifier = ref.watch(authStateProvider.notifier);
  final googleNotifier = ref.watch(googleAuthNotifierProvider.notifier);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: Listenable.merge([
      _AuthListenable(authNotifier),
      _GoogleAuthListenable(googleNotifier),
    ]),
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      final lock = ref.read(assignmentLockStateProvider).value;
      final googleAuth = ref.read(googleAuthNotifierProvider);
      final loc = state.matchedLocation;
      final onLogin = loc == '/login';
      final onBlocker = loc == '/blocker';

      // Auth gate
      final authRedirect = switch (auth) {
        AuthChecking() => null,
        Unauthenticated() => onLogin ? null : '/login',
        Authenticated() => onLogin ? '/' : null,
      };
      if (authRedirect != null) return authRedirect;

      // ClosedRemotely lock blocks every screen except /login and /blocker.
      if (lock is ClosedRemotely && !onLogin && !onBlocker) {
        return '/blocker';
      }

      // Google auth guard for /get-maps
      if (loc == '/get-maps' && googleAuth == GoogleAuthState.signedOut) {
        return '/sign-in';
      }
      if (loc == '/sign-in' && googleAuth == GoogleAuthState.signedIn) {
        return '/get-maps';
      }

      return null;
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
        path: '/sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: '/get-maps',
        builder: (context, state) => const GetMapsScreen(),
      ),
      GoRoute(
        path: '/map',
        builder: (context, state) => const MapScreen(),
      ),
      GoRoute(
        path: '/feature/:featureId',
        builder: (context, state) => SubmissionDetailScreen(
          featureId: Uri.decodeComponent(state.pathParameters['featureId']!),
        ),
      ),
      GoRoute(
        path: '/feature/:featureId/olp/result',
        builder: (context, state) {
          final featureId = Uri.decodeComponent(state.pathParameters['featureId']!);
          final submissionId = state.uri.queryParameters['submissionId'] ?? '';
          return OlpResultScreen(
            submissionId: submissionId,
            featureId: featureId,
          );
        },
      ),
      GoRoute(
        path: '/review',
        builder: (context, state) => const ReviewScreen(),
      ),
      GoRoute(
        path: '/blocker',
        builder: (context, state) => const AssignmentClosedBlocker(),
      ),
      GoRoute(
        path: '/uploads',
        builder: (context, state) => const UploadQueueScreen(),
      ),
    ],
  );
});

/// Adapts a [StateNotifier] into a [Listenable] go_router can subscribe to.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(StateNotifier<AuthState> notifier) {
    _removeListener = notifier.addListener((_) => notifyListeners());
  }

  late final void Function() _removeListener;

  @override
  void dispose() {
    _removeListener();
    super.dispose();
  }
}

/// Adapts [GoogleAuthNotifier] into a [Listenable] go_router can subscribe to.
class _GoogleAuthListenable extends ChangeNotifier {
  _GoogleAuthListenable(StateNotifier<GoogleAuthState> notifier) {
    _removeListener = notifier.addListener((_) => notifyListeners());
  }

  late final void Function() _removeListener;

  @override
  void dispose() {
    _removeListener();
    super.dispose();
  }
}
