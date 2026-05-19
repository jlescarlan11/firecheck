import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/conflict_review/data/conflict_review_repository.dart';
import 'package:firecheck/features/conflict_review/domain/local_attribution_flatten.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final conflictReviewRepositoryProvider =
    Provider<ConflictReviewRepository>((ref) {
  return ConflictReviewRepository(ref.watch(appDatabaseProvider));
});

/// Stream of submissions parked in `awaiting_user_resolution`.
final awaitingSubmissionsProvider = StreamProvider<List<Submission>>((ref) {
  return ref
      .watch(conflictReviewRepositoryProvider)
      .watchAwaitingSubmissions();
});

/// Stream of pending dedup decisions (kind=new_feature in
/// pending_resolutions). Tracks the user-pickable dedup set for now;
/// fuller "all features with possible_duplicate_of set" wiring will
/// follow once the local features table mirrors the server's dedup cols.
final pendingDedupProvider =
    StreamProvider<List<PendingResolution>>((ref) {
  return ref
      .watch(conflictReviewRepositoryProvider)
      .watchPendingDedupResolutions();
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
