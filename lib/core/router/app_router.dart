// lib/core/router/app_router.dart
import 'dart:async';

import 'package:firecheck/features/assignment/presentation/assignment_closed_blocker.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/get_maps_screen.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:firecheck/features/auth/presentation/sign_in_screen.dart';
import 'package:firecheck/features/home/presentation/home_screen.dart';
import 'package:firecheck/features/map/presentation/map_screen.dart';
import 'package:firecheck/features/review/presentation/review_screen.dart';
import 'package:firecheck/features/survey/building_form/presentation/submission_detail_screen.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/result/olp_result_screen.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _SupabaseAuthListenable(),
    redirect: (context, state) {
      final sessionAsync = ref.read(supabaseAuthStateProvider);
      final session = sessionAsync.valueOrNull;
      final lock = ref.read(assignmentLockStateProvider).value;
      final loc = state.matchedLocation;
      final onSignIn = loc == '/sign-in';
      final onBlocker = loc == '/blocker';

      if (sessionAsync.isLoading) return null;
      if (session == null && !onSignIn) return '/sign-in';
      if (session != null && onSignIn) return '/';

      if (lock is ClosedRemotely && !onSignIn && !onBlocker) return '/blocker';

      return null;
    },
    routes: [
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) {
          final sessionAsync = ref.watch(supabaseAuthStateProvider);
          if (sessionAsync.isLoading) {
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
      GoRoute(
        path: '/feature/:featureId',
        builder: (context, state) => SubmissionDetailScreen(
          featureId:
              Uri.decodeComponent(state.pathParameters['featureId']!),
        ),
      ),
      GoRoute(
        path: '/feature/:featureId/olp/result',
        builder: (context, state) {
          final featureId =
              Uri.decodeComponent(state.pathParameters['featureId']!);
          final submissionId =
              state.uri.queryParameters['submissionId'] ?? '';
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

class _SupabaseAuthListenable extends ChangeNotifier {
  _SupabaseAuthListenable() {
    try {
      _sub = Supabase.instance.client.auth.onAuthStateChange
          .listen((_) => Future.microtask(notifyListeners));
    } catch (_) {
      // Supabase not initialised (e.g. in widget tests) — listenable is a no-op.
    }
  }

  StreamSubscription<AuthState>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
