import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/review/data/review_repository.dart';
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/domain/review_validator.dart';
import 'package:flutter_test/flutter_test.dart';

Feature _building(String id) => Feature(
      id: id,
      assignmentId: 'a-1',
      featureType: 'building',
      geometryGeojson: '{}',
      isNew: false,
      status: 'complete',
      createdAt: DateTime(2026, 4, 27),
    );

Feature _road(String id) => Feature(
      id: id,
      assignmentId: 'a-1',
      featureType: 'road',
      geometryGeojson: '{}',
      isNew: false,
      status: 'complete',
      createdAt: DateTime(2026, 4, 27),
    );

Submission _sub(
  String id,
  String featureId, {
  String syncStatus = 'ready_to_upload',
  bool doesNotExist = false,
}) =>
    Submission(
      id: id,
      featureId: featureId,
      submittedBy: 'u-1',
      doesNotExist: doesNotExist,
      remarks: null,
      syncStatus: syncStatus,
      overrideReason: null,
      createdAt: DateTime(2026, 4, 27),
      updatedAt: DateTime(2026, 4, 27),
    );

BuildingAttribute _bldg(
  String submissionId, {
  String? ra9514Type,
  bool costIsExact = false,
  double? costAmount,
  String? costEstimateRange,
}) =>
    BuildingAttribute(
      submissionId: submissionId,
      cbmsId: null,
      buildingName: 'name',
      ra9514Type: ra9514Type,
      storeys: 1,
      material: 'concrete',
      costIsExact: costIsExact,
      costAmount: costAmount,
      costEstimateRange: costEstimateRange,
      fireFightingFacilitiesJson: '[]',
      fireLoadJson: '[]',
    );

RoadAttribute _roadAttrs(String submissionId, {double? widthMeters}) =>
    RoadAttribute(
      submissionId: submissionId,
      isBridge: false,
      roadName: 'Main',
      widthMeters: widthMeters,
      roadFeaturesJson: '[]',
      othersDescription: null,
    );

void main() {
  test('empty assignment → 0 features, 0 issues, no upload', () {
    final state = buildReviewState(
      const ReviewSourceData(
        features: [],
        submissions: [],
        buildingAttrs: [],
        roadAttrs: [],
        householdSurveys: [],
        photoCountsBySubmission: {},
        deadJobs: [],
      ),
    );
    expect(state.summary.totalFeatures, 0);
    expect(state.blockers, isEmpty);
    expect(state.warnings, isEmpty);
    expect(state.canStartUpload, isFalse);
  });

  test('feature with no submission → blocker feature_has_no_finalized_submission', () {
    final state = buildReviewState(
      ReviewSourceData(
        features: [_building('f-1')],
        submissions: const [],
        buildingAttrs: const [],
        roadAttrs: const [],
        householdSurveys: const [],
        photoCountsBySubmission: const {},
        deadJobs: const [],
      ),
    );
    expect(
      state.blockers.map((b) => b.code),
      contains('feature_has_no_finalized_submission'),
    );
  });

  test('complete building with no photo → photo_required blocker', () {
    final state = buildReviewState(
      ReviewSourceData(
        features: [_building('f-1')],
        submissions: [_sub('s-1', 'f-1')],
        buildingAttrs: [_bldg('s-1', ra9514Type: 'C')],
        roadAttrs: const [],
        householdSurveys: const [],
        photoCountsBySubmission: const {'s-1': 0},
        deadJobs: const [],
      ),
    );
    expect(
      state.blockers.map((b) => b.code),
      contains('photo_required'),
    );
  });

  test('building missing ra_9514_type → blocker', () {
    final state = buildReviewState(
      ReviewSourceData(
        features: [_building('f-1')],
        submissions: [_sub('s-1', 'f-1')],
        buildingAttrs: [_bldg('s-1', ra9514Type: null)],
        roadAttrs: const [],
        householdSurveys: const [],
        photoCountsBySubmission: const {'s-1': 1},
        deadJobs: const [],
      ),
    );
    expect(
      state.blockers.map((b) => b.code),
      contains('ra_9514_type_required'),
    );
  });

  test('road with width=0 → width_meters_required blocker', () {
    final state = buildReviewState(
      ReviewSourceData(
        features: [_road('f-1')],
        submissions: [_sub('s-1', 'f-1')],
        buildingAttrs: const [],
        roadAttrs: [_roadAttrs('s-1', widthMeters: 0)],
        householdSurveys: const [],
        photoCountsBySubmission: const {'s-1': 1},
        deadJobs: const [],
      ),
    );
    expect(
      state.blockers.map((b) => b.code),
      contains('width_meters_required'),
    );
  });

  test('residential building (type A) with no OLP → warning olp_residential', () {
    final state = buildReviewState(
      ReviewSourceData(
        features: [_building('f-1')],
        submissions: [_sub('s-1', 'f-1')],
        buildingAttrs: [_bldg('s-1', ra9514Type: 'A')],
        roadAttrs: const [],
        householdSurveys: const [],
        photoCountsBySubmission: const {'s-1': 1},
        deadJobs: const [],
      ),
    );
    expect(
      state.warnings.map((w) => w.code),
      contains('olp_residential'),
    );
  });

  test('cost_is_exact=true with null cost_amount → warning cost_amount_missing', () {
    final state = buildReviewState(
      ReviewSourceData(
        features: [_building('f-1')],
        submissions: [_sub('s-1', 'f-1')],
        buildingAttrs: [_bldg('s-1', ra9514Type: 'C', costIsExact: true)],
        roadAttrs: const [],
        householdSurveys: const [],
        photoCountsBySubmission: const {'s-1': 1},
        deadJobs: const [],
      ),
    );
    expect(
      state.warnings.map((w) => w.code),
      contains('cost_amount_missing'),
    );
  });

  test('does_not_exist=true short-circuits ra_9514_type/width blockers but keeps photo blocker', () {
    final stateBuilding = buildReviewState(
      ReviewSourceData(
        features: [_building('f-1')],
        submissions: [_sub('s-1', 'f-1', doesNotExist: true)],
        buildingAttrs: [_bldg('s-1', ra9514Type: null)],
        roadAttrs: const [],
        householdSurveys: const [],
        photoCountsBySubmission: const {'s-1': 0},
        deadJobs: const [],
      ),
    );
    expect(
      stateBuilding.blockers.map((b) => b.code),
      isNot(contains('ra_9514_type_required')),
    );
    expect(
      stateBuilding.blockers.map((b) => b.code),
      contains('photo_required'),
    );
  });

  test('dead jobs surface as DeadJobRow rows', () {
    final state = buildReviewState(
      ReviewSourceData(
        features: const [],
        submissions: const [],
        buildingAttrs: const [],
        roadAttrs: const [],
        householdSurveys: const [],
        photoCountsBySubmission: const {},
        deadJobs: const [
          DeadJobRow(
            jobId: 'j-1',
            entityType: 'photo',
            entityId: 'p-1',
            attempts: 5,
            lastError: 'Network error',
          ),
        ],
      ),
    );
    expect(state.deadJobs, hasLength(1));
    expect(state.deadJobs.first.jobId, 'j-1');
  });

  test('summary counts: 2 features, 1 complete (with photo), 1 incomplete', () {
    final state = buildReviewState(
      ReviewSourceData(
        features: [_building('f-1'), _building('f-2')],
        submissions: [
          _sub('s-1', 'f-1'),
          _sub('s-2', 'f-2'),
        ],
        buildingAttrs: [
          _bldg('s-1', ra9514Type: 'C'),
          _bldg('s-2', ra9514Type: null),
        ],
        roadAttrs: const [],
        householdSurveys: const [],
        photoCountsBySubmission: const {'s-1': 1, 's-2': 0},
        deadJobs: const [],
      ),
    );
    expect(state.summary.totalFeatures, 2);
    expect(state.summary.completeFeatures, 1);
    expect(state.summary.incompleteFeatures, 1);
    expect(state.summary.photosPending, 1);
  });

  test('canStartUpload=true when no blockers and at least 1 complete', () {
    final state = buildReviewState(
      ReviewSourceData(
        features: [_building('f-1')],
        submissions: [_sub('s-1', 'f-1')],
        buildingAttrs: [_bldg('s-1', ra9514Type: 'C')],
        roadAttrs: const [],
        householdSurveys: const [],
        photoCountsBySubmission: const {'s-1': 1},
        deadJobs: const [],
      ),
    );
    expect(state.canStartUpload, isTrue);
  });
}
