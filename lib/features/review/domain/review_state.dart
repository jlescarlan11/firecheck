import 'package:firecheck/features/review/domain/upload_progress.dart';
import 'package:flutter/foundation.dart';

/// Snapshot of everything the Review screen renders.
class ReviewState {
  const ReviewState({
    required this.summary,
    required this.warnings,
    required this.blockers,
    required this.deadJobs,
    required this.upload,
  });

  final ReviewSummary summary;
  final List<ReviewIssue> warnings;
  final List<ReviewIssue> blockers;
  final List<DeadJobRow> deadJobs;
  final UploadProgress upload;

  /// Start Upload is enabled when:
  ///  - no blockers
  ///  - at least one complete-or-skipped feature to upload
  ///  - we're idle (not mid-upload)
  bool get canStartUpload =>
      blockers.isEmpty &&
      summary.completeFeatures > 0 &&
      upload is Idle;
}

@immutable
class ReviewSummary {
  const ReviewSummary({
    required this.totalFeatures,
    required this.completeFeatures,
    required this.incompleteFeatures,
    required this.newFeaturesAdded,
    required this.photosPending,
  });

  final int totalFeatures;
  final int completeFeatures;
  final int incompleteFeatures;
  final int newFeaturesAdded;
  final int photosPending;

  @override
  bool operator ==(Object other) =>
      other is ReviewSummary &&
      other.totalFeatures == totalFeatures &&
      other.completeFeatures == completeFeatures &&
      other.incompleteFeatures == incompleteFeatures &&
      other.newFeaturesAdded == newFeaturesAdded &&
      other.photosPending == photosPending;

  @override
  int get hashCode => Object.hash(
        totalFeatures,
        completeFeatures,
        incompleteFeatures,
        newFeaturesAdded,
        photosPending,
      );
}

enum ReviewSeverity { blocker, warning }

class ReviewIssue {
  const ReviewIssue({
    required this.featureId,
    required this.featureLabel,
    required this.severity,
    required this.code,
    required this.messageKey,
  });

  final String featureId;
  final String featureLabel;
  final ReviewSeverity severity;

  /// Stable identifier for the rule (e.g. `photo_required`, `ra_9514_type_required`).
  /// Used for grouping + analytics. NOT shown to the user.
  final String code;

  /// ARB key for the user-facing message (e.g. `issuePhotoRequired`).
  final String messageKey;
}

class DeadJobRow {
  const DeadJobRow({
    required this.jobId,
    required this.entityType,
    required this.entityId,
    required this.attempts,
    required this.lastError,
  });

  final String jobId;
  final String entityType;
  final String entityId;
  final int attempts;
  final String lastError;
}
