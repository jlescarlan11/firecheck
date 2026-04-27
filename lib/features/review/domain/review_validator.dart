import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/review/data/review_repository.dart';
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/domain/upload_progress.dart';

/// Pure validator: takes a snapshot of source rows and produces ReviewState.
///
/// Per master spec §10. Treats `does_not_exist=true` as the existing
/// validateBuildingForm/validateRoadForm do — short-circuits content
/// blockers, but photo is always required.
ReviewState buildReviewState(ReviewSourceData data) {
  final blockers = <ReviewIssue>[];
  final warnings = <ReviewIssue>[];

  final submissionsByFeature = <String, List<Submission>>{};
  for (final s in data.submissions) {
    submissionsByFeature.putIfAbsent(s.featureId, () => []).add(s);
  }
  final buildingBySub = {for (final b in data.buildingAttrs) b.submissionId: b};
  final roadBySub = {for (final r in data.roadAttrs) r.submissionId: r};
  final householdBySub = {
    for (final h in data.householdSurveys) h.submissionId: h,
  };

  var completeFeatures = 0;
  var incompleteFeatures = 0;
  var newFeaturesAdded = 0;
  var photosPending = 0;

  bool isFinalized(Submission s) =>
      s.syncStatus == 'ready_to_upload' ||
      s.syncStatus == 'queued' ||
      s.syncStatus == 'uploaded';

  for (final f in data.features) {
    if (f.isNew) newFeaturesAdded++;
    final subs = submissionsByFeature[f.id] ?? const <Submission>[];
    final finalized = subs.where(isFinalized).toList();
    if (finalized.isEmpty) {
      incompleteFeatures++;
      blockers.add(
        ReviewIssue(
          featureId: f.id,
          featureLabel: _featureLabel(f),
          severity: ReviewSeverity.blocker,
          code: 'feature_has_no_finalized_submission',
          messageKey: 'issueFeatureNoSubmission',
        ),
      );
      continue;
    }
    var anyComplete = false;
    for (final sub in finalized) {
      final photoCount = data.photoCountsBySubmission[sub.id] ?? 0;
      var subBlockers = 0;

      if (photoCount < 1) {
        subBlockers++;
        photosPending++;
        blockers.add(
          ReviewIssue(
            featureId: f.id,
            featureLabel: _featureLabel(f),
            severity: ReviewSeverity.blocker,
            code: 'photo_required',
            messageKey: 'issuePhotoRequired',
          ),
        );
      }

      if (!sub.doesNotExist) {
        if (f.featureType == 'building') {
          final b = buildingBySub[sub.id];
          if (b == null || b.ra9514Type == null) {
            subBlockers++;
            blockers.add(
              ReviewIssue(
                featureId: f.id,
                featureLabel: _featureLabel(f),
                severity: ReviewSeverity.blocker,
                code: 'ra_9514_type_required',
                messageKey: 'issueRa9514Required',
              ),
            );
          } else {
            // Warning: residential without OLP.
            final isResidential = b.ra9514Type == 'A' || b.ra9514Type == 'B';
            final olp = householdBySub[sub.id];
            if (isResidential && (olp == null || olp.completedAt == null)) {
              warnings.add(
                ReviewIssue(
                  featureId: f.id,
                  featureLabel: _featureLabel(f),
                  severity: ReviewSeverity.warning,
                  code: 'olp_residential',
                  messageKey: 'issueOlpResidential',
                ),
              );
            }
            // Warning: cost_is_exact but no amount.
            if (b.costIsExact && b.costAmount == null) {
              warnings.add(
                ReviewIssue(
                  featureId: f.id,
                  featureLabel: _featureLabel(f),
                  severity: ReviewSeverity.warning,
                  code: 'cost_amount_missing',
                  messageKey: 'issueCostAmountMissing',
                ),
              );
            }
          }
        } else if (f.featureType == 'road') {
          final r = roadBySub[sub.id];
          if (r == null || (r.widthMeters ?? 0) <= 0) {
            subBlockers++;
            blockers.add(
              ReviewIssue(
                featureId: f.id,
                featureLabel: _featureLabel(f),
                severity: ReviewSeverity.blocker,
                code: 'width_meters_required',
                messageKey: 'issueWidthRequired',
              ),
            );
          }
        }
      }

      if (subBlockers == 0) anyComplete = true;
    }
    if (anyComplete) {
      completeFeatures++;
    } else {
      incompleteFeatures++;
    }
  }

  final summary = ReviewSummary(
    totalFeatures: data.features.length,
    completeFeatures: completeFeatures,
    incompleteFeatures: incompleteFeatures,
    newFeaturesAdded: newFeaturesAdded,
    photosPending: photosPending,
  );

  return ReviewState(
    summary: summary,
    warnings: warnings,
    blockers: blockers,
    deadJobs: data.deadJobs,
    upload: const Idle(),
  );
}

String _featureLabel(Feature f) {
  // Short, stable label for grouping. Detail screen owns the friendly name.
  final shortId = f.id.length > 6 ? f.id.substring(0, 6) : f.id;
  return '${f.featureType[0].toUpperCase()}${f.featureType.substring(1)} $shortId';
}
