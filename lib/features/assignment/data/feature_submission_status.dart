// lib/features/assignment/data/feature_submission_status.dart
import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/domain/submission_sync_status.dart';
import 'package:rxdart/rxdart.dart';

enum FeatureSubmissionStatus {
  /// No submission exists locally or remotely.
  unsurveyed,

  /// Local draft only — form in progress, not finalized.
  draft,

  /// Finalized locally, queued/uploading but not yet acknowledged
  /// by the server.
  pendingUpload,

  /// My submission has reached the server.
  submittedByMe,

  /// Someone else's submission is the current canonical row for this
  /// feature (delivered via realtime / remote cache).
  submittedByOther,

  /// The latest submission conflicts and is waiting on the user to
  /// pick a side in the review UI.
  needsResolution,
}

class FeatureSubmissionStatusResolver {
  FeatureSubmissionStatusResolver(this._db);
  final AppDatabase _db;

  /// Streams a featureId → status map for all features in [assignmentId].
  /// Re-emits whenever local submissions or the remote cache changes.
  Stream<Map<String, FeatureSubmissionStatus>> watchByAssignment({
    required String assignmentId,
    required String? currentUserId,
  }) {
    final featureIdsQuery = (_db.selectOnly(_db.features)
          ..addColumns([_db.features.id])
          ..where(_db.features.assignmentId.equals(assignmentId)))
        .watch()
        .map((rows) => rows.map((r) => r.read(_db.features.id)!).toSet());

    final localSubs = (_db.select(_db.submissions)).watch();

    final remoteSubs = (_db.select(_db.remoteAttributionsCache)
          ..where((c) =>
              c.assignmentId.equals(assignmentId) &
              c.supersededAt.isNull()))
        .watch();

    return Rx.combineLatest3<Set<String>, List<Submission>,
        List<RemoteAttributionsCacheData>,
        Map<String, FeatureSubmissionStatus>>(
      featureIdsQuery,
      localSubs,
      remoteSubs,
      (featureIds, locals, remotes) {
        final result = <String, FeatureSubmissionStatus>{};

        // 1. Seed every feature as unsurveyed.
        for (final id in featureIds) {
          result[id] = FeatureSubmissionStatus.unsurveyed;
        }

        // 2. Remote (canonical) submissions from other users take priority
        //    over the unsurveyed default but lose to any local row, since
        //    a local row means the current user is mid-edit/upload.
        for (final r in remotes) {
          if (!featureIds.contains(r.featureId)) continue;
          if (r.submittedBy == currentUserId) continue;
          result[r.featureId] = FeatureSubmissionStatus.submittedByOther;
        }

        // 3. Local submissions override — they represent the current
        //    user's own state, which is what the UI gates affordances on.
        for (final s in locals) {
          if (!featureIds.contains(s.featureId)) continue;
          result[s.featureId] = _mapLocal(s.syncStatus);
        }

        return result;
      },
    ).distinct();
  }

  FeatureSubmissionStatus _mapLocal(String syncStatus) {
    switch (syncStatus) {
      case SubmissionSyncStatus.draft:
      case SubmissionSyncStatus.inProgress:
        return FeatureSubmissionStatus.draft;
      case SubmissionSyncStatus.queued:
        return FeatureSubmissionStatus.pendingUpload;
      case SubmissionSyncStatus.uploaded:
        return FeatureSubmissionStatus.submittedByMe;
      case SubmissionSyncStatus.awaitingUserResolution:
        return FeatureSubmissionStatus.needsResolution;
      case SubmissionSyncStatus.withdrawn:
        return FeatureSubmissionStatus.unsurveyed;
      default:
        return FeatureSubmissionStatus.draft;
    }
  }
}
