import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/forms/field_requirements.dart';
import 'package:firecheck/core/forms/form_definition.dart';
import 'package:firecheck/features/review/data/review_repository.dart';
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/domain/review_validator.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_applicability.dart';
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
      isAdditionalObservation: false,
      id: id,
      featureId: featureId,
      submittedBy: 'u-1',
      doesNotExist: doesNotExist,
      formVersion: 'legacy-v1',
      syncStatus: syncStatus,
      createdAt: DateTime(2026, 4, 27),
      updatedAt: DateTime(2026, 4, 27),
    );

BuildingAttribute _bldg(
  String submissionId, {
  String? ra9514Type,
  String? cbmsId,
  String facilities = '[]',
  bool costIsExact = false,
  double? costAmount,
  String? costEstimateRange,
}) =>
    BuildingAttribute(
      submissionId: submissionId,
      buildingName: 'name',
      cbmsId: cbmsId,
      ra9514Type: ra9514Type,
      storeys: 1,
      material: 'concrete',
      costIsExact: costIsExact,
      costAmount: costAmount,
      costEstimateRange: costEstimateRange,
      fireFightingFacilitiesJson: facilities,
      fireLoadJson: '[]',
    );

RoadAttribute _roadAttrs(String submissionId, {double? widthMeters}) =>
    RoadAttribute(
      submissionId: submissionId,
      isBridge: false,
      roadName: 'Main',
      widthMeters: widthMeters,
      roadFeaturesJson: '[]',
    );

void main() {
  test('review boundary context stays bound to the source assignment', () {
    const boundary =
        '{"type":"Polygon","coordinates":[[[0,0],[1,0],[1,1],[0,1],[0,0]]]}';
    final definition = FormDefinition.fromJson(const {
      'version': 'boundary',
      'name': 'Boundary',
      'visibilityRules': [
        {
          'target': 'building.section.fireFightingFacilities',
          'conditions': [
            {
              'source': 'geometry',
              'key': 'distanceFromBoundaryMeters',
              'operator': 'not_equals',
              'value': 0,
            }
          ],
        }
      ],
    });
    ReviewSourceData source(String assignment) => ReviewSourceData(
          assignmentId: assignment,
          assignmentBoundaryGeojson: boundary,
          features: [
            _building('f').copyWith(
              geometryGeojson: '{"type":"Point","coordinates":[0,0]}',
            ),
          ],
          submissions: [_sub('s', 'f')],
          buildingAttrs: [_bldg('s', ra9514Type: 'C')],
          roadAttrs: [],
          householdSurveys: [],
          photoCountsBySubmission: {'s': 1},
          deadJobs: [],
        );
    final requirements =
        parseFieldRequirements('building.fireFightingFacilities=required');
    expect(
      buildReviewState(
        source('a-1'),
        requirements: requirements,
        definition: definition,
      ).blockers,
      isEmpty,
    );
    expect(
      buildReviewState(
        source('other'),
        requirements: requirements,
        definition: definition,
      ).blockers.map((b) => b.code),
      contains('fire_fighting_facilities_required'),
    );
  });

  for (final section in ['identity', 'fireFightingFacilities']) {
    test('definition-hidden $section skips its required new answer', () {
      final hiddenField =
          section == 'identity' ? 'cbmsId' : 'fireFightingFacilities';
      final definition = FormDefinition.fromJson({
        'version': 'visibility-test',
        'name': 'Visibility test',
        'visibilityRules': [
          {
            'target': 'building.section.$section',
            'conditions': const [
              {
                'source': 'answer',
                'key': 'building.costIsExact',
                'operator': 'equals',
                'value': true,
              }
            ],
          }
        ],
      });
      const requirements = FieldRequirements({
        'building.buildingName': false,
        'building.ra9514Type': false,
        'building.storeys': false,
        'building.material': false,
        'building.cost': false,
        'building.fireLoad': false,
        'building.cbmsId': true,
        'building.fireFightingFacilities': true,
      });
      final source = ReviewSourceData(
        features: [_building('f')],
        submissions: [_sub('s', 'f')],
        buildingAttrs: [_bldg('s', ra9514Type: 'C')],
        roadAttrs: [],
        householdSurveys: [],
        photoCountsBySubmission: {'s': 1},
        deadJobs: [],
      );
      final state = buildReviewState(
        source,
        requirements: requirements,
        definition: definition,
      );
      final hiddenCode = hiddenField == 'cbmsId'
          ? 'cbms_id_required'
          : 'fire_fighting_facilities_required';
      expect(state.blockers.map((b) => b.code), isNot(contains(hiddenCode)));
      expect(state.blockers.length, 1);
    });
  }
  test(
      'review enforces configured CBMS and facilities, preserving legacy defaults',
      () {
    ReviewSourceData source({bool answered = false, bool missing = false}) =>
        ReviewSourceData(
          features: [_building('f')],
          submissions: [_sub('s', 'f')],
          buildingAttrs: missing
              ? []
              : [
                  _bldg(
                    's',
                    ra9514Type: 'C',
                    cbmsId: answered ? 'local / ID' : null,
                    facilities: answered ? '["None"]' : '[]',
                  ),
                ],
          roadAttrs: [],
          householdSurveys: [],
          photoCountsBySubmission: {'s': 1},
          deadJobs: [],
        );
    final requirements = parseFieldRequirements(
      'building.cbmsId=required\nbuilding.fireFightingFacilities=required',
    );
    expect(buildReviewState(source()).blockers, isEmpty);
    final required = buildReviewState(source(), requirements: requirements);
    expect(
      required.blockers.map((b) => b.code),
      containsAll(['cbms_id_required', 'fire_fighting_facilities_required']),
    );
    expect(
      buildReviewState(source(answered: true), requirements: requirements)
          .blockers,
      isEmpty,
    );
    expect(
      buildReviewState(
        source(),
        requirements: requirements,
        hiddenBuildingFields: {
          BuildingFormField.cbmsId,
          BuildingFormField.fireFightingFacilities,
        },
      ).blockers,
      isEmpty,
    );
    expect(
      buildReviewState(
        source(),
        requirements: parseFieldRequirements(
          'building.cbmsId=optional\nbuilding.fireFightingFacilities=optional',
        ),
      ).blockers,
      isEmpty,
    );
    expect(
      buildReviewState(source(missing: true), requirements: requirements)
          .blockers
          .map((b) => b.code),
      containsAll(['cbms_id_required', 'fire_fighting_facilities_required']),
    );
  });

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

  test(
      'feature with no submission → warning feature_has_no_finalized_submission',
      () {
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
      state.warnings.map((w) => w.code),
      contains('feature_has_no_finalized_submission'),
    );
    expect(
      state.blockers.map((b) => b.code),
      isNot(contains('feature_has_no_finalized_submission')),
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
        buildingAttrs: [_bldg('s-1')],
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

  test('residential building (type A) with no OLP → warning olp_residential',
      () {
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

  test('cost_is_exact=true with null cost_amount → warning cost_amount_missing',
      () {
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

  test(
      'does_not_exist=true short-circuits ra_9514_type/width blockers but keeps photo blocker',
      () {
    final stateBuilding = buildReviewState(
      ReviewSourceData(
        features: [_building('f-1')],
        submissions: [_sub('s-1', 'f-1', doesNotExist: true)],
        buildingAttrs: [_bldg('s-1')],
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
      const ReviewSourceData(
        features: [],
        submissions: [],
        buildingAttrs: [],
        roadAttrs: [],
        householdSurveys: [],
        photoCountsBySubmission: {},
        deadJobs: [
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
          _bldg('s-2'),
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
