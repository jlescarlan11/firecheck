import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/conflict_review/data/conflict_review_repository.dart';
import 'package:firecheck/features/conflict_review/data/dedup_comparison_repository.dart';
import 'package:firecheck/features/conflict_review/domain/dedup_comparison.dart';
import 'package:firecheck/features/conflict_review/domain/local_attribution_flatten.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final conflictReviewRepositoryProvider =
    Provider<ConflictReviewRepository>((ref) {
  return ConflictReviewRepository(ref.watch(appDatabaseProvider));
});

/// Stream of submissions parked in `awaiting_user_resolution`.
final awaitingSubmissionsProvider = StreamProvider<List<Submission>>((ref) {
  return ref.watch(conflictReviewRepositoryProvider).watchAwaitingSubmissions();
});

/// Stream of features awaiting dedup review — `pendingDedupOf` is set
/// by the worker when `submit_new_feature_with_dedup_check` returns
/// `dedup_pending`. Cleared when the matching `new_feature_resolve`
/// job runs to completion.
final pendingDedupProvider = StreamProvider<List<Feature>>((ref) {
  return ref
      .watch(conflictReviewRepositoryProvider)
      .watchPendingDedupFeatures();
});

/// Flattened local attribution for a given submission, refreshed when
/// the submission or its typed child row changes (Drift's reactivity).
final localAttributionForSubmissionProvider =
    FutureProvider.family<Map<String, Object?>, String>(
  (ref, submissionId) async {
    final db = ref.watch(appDatabaseProvider);
    return flattenLocalAttributionForDisplay(
      db: db,
      submissionId: submissionId,
    );
  },
);

/// Banner count for the home screen: how many local submissions are
/// awaiting user action right now.
final awaitingResolutionCountProvider = Provider<int>((ref) {
  final subs = ref.watch(awaitingSubmissionsProvider).valueOrNull ?? const [];
  final dedup = ref.watch(pendingDedupProvider).valueOrNull ?? const [];
  return subs.length + dedup.length;
});

final dedupComparisonRepositoryProvider = Provider<DedupComparisonRepository>(
  (ref) => DedupComparisonRepository(ref.watch(appDatabaseProvider)),
);

/// Rebuild on account/map changes; do not retain the previous map's comparison.
final dedupComparisonProvider = StreamProvider.autoDispose
    .family<DedupComparison?, String>((ref, featureId) {
  final assignment = ref.watch(currentAssignmentProvider).valueOrNull;
  final account = ref.watch(currentUserIdProvider);
  if (assignment == null || account == null) return Stream.value(null);
  return ref.watch(dedupComparisonRepositoryProvider).watch(
        featureId: featureId,
        assignmentId: assignment.id,
        accountId: account,
      );
});
