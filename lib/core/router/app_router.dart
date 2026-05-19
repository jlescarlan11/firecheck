// lib/core/router/app_router.dart
import 'package:firecheck/features/assignment/presentation/assignment_closed_blocker.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/get_maps_screen.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:firecheck/features/auth/presentation/sign_in_screen.dart';
import 'package:firecheck/features/home/presentation/home_screen.dart';
import 'package:firecheck/features/conflict_review/presentation/attribution_conflict_screen.dart';
import 'package:firecheck/features/conflict_review/presentation/conflict_review_list_screen.dart';
import 'package:firecheck/features/conflict_review/presentation/dedup_review_screen.dart';
import 'package:firecheck/features/map/presentation/map_screen.dart';
import 'package:firecheck/features/remote_activity/presentation/remote_activity_list_screen.dart';
import 'package:firecheck/features/remote_activity/presentation/remote_attribution_detail_screen.dart';
import 'package:firecheck/features/review/presentation/review_screen.dart';
import 'package:firecheck/features/survey/building_form/presentation/submission_detail_screen.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/result/olp_result_screen.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  // Seed from current provider values so redirect has data on first evaluation.
  var sessionAsync = ref.read(supabaseAuthStateProvider);
  var lock = ref.read(assignmentLockStateProvider).value;

  // ValueNotifier drives GoRouter re-evaluation without any ref call in redirect.
  final notifier = ValueNotifier<int>(0);

  ref.listen(supabaseAuthStateProvider, (_, next) {
    sessionAsync = next;
    notifier.value++;
  });

  ref.listen(assignmentLockStateProvider, (_, next) {
    lock = next.value;
    notifier.value++;
  });

  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: (context, state) {
      final session = sessionAsync.valueOrNull;
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
        builder: (context, state) => Consumer(
          builder: (context, ref, _) {
            final session = ref.watch(supabaseAuthStateProvider);
            if (session.isLoading) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return const HomeScreen();
          },
        ),
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
      GoRoute(
        path: '/remote-activity',
        builder: (context, state) => const RemoteActivityListScreen(),
      ),
      GoRoute(
        path: '/remote-activity/:featureId',
        builder: (context, state) => RemoteAttributionDetailScreen(
          featureId: Uri.decodeComponent(state.pathParameters['featureId']!),
        ),
      ),
      GoRoute(
        path: '/resolve',
        builder: (context, state) => const ConflictReviewListScreen(),
      ),
      GoRoute(
        path: '/resolve/attribution/:submissionId',
        builder: (context, state) => AttributionConflictScreen(
          submissionId:
              Uri.decodeComponent(state.pathParameters['submissionId']!),
        ),
      ),
      GoRoute(
        path: '/resolve/dedup/:featureId',
        builder: (context, state) => DedupReviewScreen(
          featureId: Uri.decodeComponent(state.pathParameters['featureId']!),
        ),
      ),
    ],
  );
});
