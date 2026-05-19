import 'package:drift/drift.dart';
import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/remote_activity/domain/remote_attribution_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// All non-superseded remote attributions for the *current* assignment,
/// excluding the current user's own. The exclusion rule is "show me what
/// OTHER enumerators did" — my own work already lives in the local
/// submissions table.
///
/// Synchronous Stream-returning body (not `async*`) so a transient
/// "assignment still loading" state doesn't terminate the stream — when
/// the assignment resolves, Riverpod re-evaluates and swaps in the real
/// Drift watch.
final othersRemoteAttributionsProvider =
    StreamProvider<List<RemoteAttributionView>>((ref) {
  final assignment = ref.watch(currentAssignmentProvider).value;
  if (assignment == null) {
    return Stream<List<RemoteAttributionView>>.value(const []);
  }
  final me = ref.watch(currentUserIdProvider);
  final db = ref.watch(appDatabaseProvider);

  final query = db.select(db.remoteAttributionsCache)
    ..where((t) =>
        t.assignmentId.equals(assignment.id) &
        t.supersededAt.isNull() &
        (me == null
            ? const Constant<bool>(true)
            : t.submittedBy.isNotValue(me) | t.submittedBy.isNull()),)
    ..orderBy([
      (t) => OrderingTerm(expression: t.submittedAt, mode: OrderingMode.desc),
    ]);

  return query.watch().map(
        (rows) => rows.map(RemoteAttributionView.fromRow).toList(),
      );
});

/// Convenience: the canonical remote attribution (if any) for a given
/// feature, by anyone OTHER than the current user. Phase 5 will read
/// this at upload time to compute base_version_id.
final remoteAttributionForFeatureProvider =
    StreamProvider.family<RemoteAttributionView?, String>(
  (ref, featureId) {
    final me = ref.watch(currentUserIdProvider);
    final db = ref.watch(appDatabaseProvider);
    final query = db.select(db.remoteAttributionsCache)
      ..where((t) =>
          t.featureId.equals(featureId) &
          t.supersededAt.isNull() &
          (me == null
              ? const Constant<bool>(true)
              : t.submittedBy.isNotValue(me) | t.submittedBy.isNull()),)
      ..orderBy([
        (t) =>
            OrderingTerm(expression: t.submittedAt, mode: OrderingMode.desc),
      ])
      ..limit(1);

    return query.watchSingleOrNull().map(
          (row) => row == null ? null : RemoteAttributionView.fromRow(row),
        );
  },
);

/// Count of features (not submissions) with at least one non-superseded
/// remote attribution authored by a different user. Used by the
/// `RemoteActivityChip` badge.
final remoteActivityCountProvider = Provider<int>((ref) {
  final attribs = ref.watch(othersRemoteAttributionsProvider).valueOrNull ?? [];
  // Distinct by feature_id — a feature can have multiple non-superseded
  // submissions during conflict resolution windows.
  return attribs.map((a) => a.featureId).toSet().length;
});
