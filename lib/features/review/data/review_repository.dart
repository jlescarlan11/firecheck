import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/review/domain/review_state.dart';

/// Snapshot the validator consumes. Filled in by the repository in Task 7.
class ReviewSourceData {
  const ReviewSourceData({
    required this.features,
    required this.submissions,
    required this.buildingAttrs,
    required this.roadAttrs,
    required this.householdSurveys,
    required this.photoCountsBySubmission,
    required this.deadJobs,
  });

  final List<Feature> features;
  final List<Submission> submissions;
  final List<BuildingAttribute> buildingAttrs;
  final List<RoadAttribute> roadAttrs;
  final List<HouseholdSurvey> householdSurveys;
  final Map<String, int> photoCountsBySubmission;
  final List<DeadJobRow> deadJobs;
}
