import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/review/domain/review_state.dart';

/// Snapshot the validator consumes.
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

class ReviewRepository {
  ReviewRepository(this._db);
  final AppDatabase _db;

  /// Combined stream that re-emits whenever any source table changes for
  /// this assignment. Implementation: a single customSelect using a
  /// constant SELECT 1 with a `readsFrom` set drives the stream cadence;
  /// each emission triggers a fan-in fetch of the actual rows.
  Stream<ReviewSourceData> streamForAssignment(String assignmentId) {
    final trigger = _db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            _db.features,
            _db.submissions,
            _db.buildingAttributes,
            _db.roadAttributes,
            _db.householdSurveys,
            _db.photos,
            _db.syncJobs,
          },
        )
        .watch();

    return trigger.asyncMap((_) async => _snapshot(assignmentId));
  }

  Future<ReviewSourceData> _snapshot(String assignmentId) async {
    final features = await (_db.select(_db.features)
          ..where((t) => t.assignmentId.equals(assignmentId)))
        .get();
    final featureIds = features.map((f) => f.id).toList();

    final submissions = featureIds.isEmpty
        ? <Submission>[]
        : await (_db.select(_db.submissions)
              ..where((t) => t.featureId.isIn(featureIds)))
            .get();
    final submissionIds = submissions.map((s) => s.id).toList();

    final buildingAttrs = submissionIds.isEmpty
        ? <BuildingAttribute>[]
        : await (_db.select(_db.buildingAttributes)
              ..where((t) => t.submissionId.isIn(submissionIds)))
            .get();
    final roadAttrs = submissionIds.isEmpty
        ? <RoadAttribute>[]
        : await (_db.select(_db.roadAttributes)
              ..where((t) => t.submissionId.isIn(submissionIds)))
            .get();
    final householdSurveys = submissionIds.isEmpty
        ? <HouseholdSurvey>[]
        : await (_db.select(_db.householdSurveys)
              ..where((t) => t.submissionId.isIn(submissionIds)))
            .get();

    final photoCounts = <String, int>{};
    if (submissionIds.isNotEmpty) {
      final photoRows = await (_db.select(_db.photos)
            ..where((t) => t.submissionId.isIn(submissionIds)))
          .get();
      for (final p in photoRows) {
        photoCounts[p.submissionId] = (photoCounts[p.submissionId] ?? 0) + 1;
      }
    }

    final deadJobRows = await _db.customSelect(
      '''
      SELECT j.id, j.entity_type, j.entity_id, j.attempts, j.last_error
      FROM sync_jobs j
      WHERE j.status = 'dead'
      AND (
        (j.entity_type = 'submission' AND j.entity_id IN (
          SELECT s.id FROM submissions s
          JOIN features f ON f.id = s.feature_id
          WHERE f.assignment_id = ?
        ))
        OR (j.entity_type = 'photo' AND j.entity_id IN (
          SELECT p.id FROM photos p
          JOIN submissions s ON s.id = p.submission_id
          JOIN features f ON f.id = s.feature_id
          WHERE f.assignment_id = ?
        ))
        OR (j.entity_type = 'new_feature' AND j.entity_id IN (
          SELECT id FROM features WHERE assignment_id = ?
        ))
      )
      ORDER BY j.created_at ASC
      ''',
      variables: [
        Variable.withString(assignmentId),
        Variable.withString(assignmentId),
        Variable.withString(assignmentId),
      ],
      readsFrom: {_db.syncJobs, _db.submissions, _db.features, _db.photos},
    ).get();

    final deadJobs = deadJobRows
        .map((r) => DeadJobRow(
              jobId: r.read<String>('id'),
              entityType: r.read<String>('entity_type'),
              entityId: r.read<String>('entity_id'),
              attempts: r.read<int>('attempts'),
              lastError: r.read<String?>('last_error') ?? '',
            ))
        .toList();

    return ReviewSourceData(
      features: features,
      submissions: submissions,
      buildingAttrs: buildingAttrs,
      roadAttrs: roadAttrs,
      householdSurveys: householdSurveys,
      photoCountsBySubmission: photoCounts,
      deadJobs: deadJobs,
    );
  }
}
