import 'package:firecheck/core/db/database.dart';

class SubmissionPayloadBuilder {
  SubmissionPayloadBuilder(this._db);
  final AppDatabase _db;

  Future<Map<String, dynamic>> build(String submissionId) async {
    final submission = await (_db.select(_db.submissions)
          ..where((t) => t.id.equals(submissionId)))
        .getSingle();
    final feature = await (_db.select(_db.features)
          ..where((t) => t.id.equals(submission.featureId)))
        .getSingle();
    final building = await (_db.select(_db.buildingAttributes)
          ..where((t) => t.submissionId.equals(submissionId)))
        .getSingleOrNull();
    final road = await (_db.select(_db.roadAttributes)
          ..where((t) => t.submissionId.equals(submissionId)))
        .getSingleOrNull();
    final household = await (_db.select(_db.householdSurveys)
          ..where((t) => t.submissionId.equals(submissionId)))
        .getSingleOrNull();

    return <String, dynamic>{
      'submission': _submissionToJson(submission),
      'feature_type': feature.featureType,
      'building_attributes':
          building == null ? null : _buildingToJson(building),
      'road_attributes': road == null ? null : _roadToJson(road),
      'household_survey':
          household == null ? null : _householdToJson(household),
    };
  }

  Map<String, dynamic> _submissionToJson(Submission s) => {
        'id': s.id,
        'feature_id': s.featureId,
        'submitted_by': s.submittedBy,
        'does_not_exist': s.doesNotExist,
        'remarks': s.remarks,
        'sync_status': s.syncStatus,
        'override_reason': s.overrideReason,
        'created_at': s.createdAt.toIso8601String(),
        'updated_at': s.updatedAt.toIso8601String(),
      };

  Map<String, dynamic> _buildingToJson(BuildingAttribute b) => {
        'submission_id': b.submissionId,
        'cbms_id': b.cbmsId,
        'building_name': b.buildingName,
        'ra_9514_type': b.ra9514Type,
        'storeys': b.storeys,
        'material': b.material,
        'cost_is_exact': b.costIsExact,
        'cost_amount': b.costAmount,
        'cost_estimate_range': b.costEstimateRange,
        'fire_fighting_facilities_json': b.fireFightingFacilitiesJson,
        'fire_load_json': b.fireLoadJson,
      };

  Map<String, dynamic> _roadToJson(RoadAttribute r) => {
        'submission_id': r.submissionId,
        'is_bridge': r.isBridge,
        'road_name': r.roadName,
        'width_meters': r.widthMeters,
        'road_features_json': r.roadFeaturesJson,
        'others_description': r.othersDescription,
      };

  Map<String, dynamic> _householdToJson(HouseholdSurvey h) => {
        'submission_id': h.submissionId,
        'construction_details_json': h.constructionDetailsJson,
        'kaayusan_json': h.kaayusanJson,
        'koneksyong_elektrikal_json': h.koneksyongElektrikalJson,
        'kusina_json': h.kusinaJson,
        'daanan_o_labasan_json': h.daananOLabasanJson,
        'lebel_ng_kahinaan': h.lebelNgKahinaan,
        'safety_suggestions': h.safetySuggestions,
        'homeowner_acknowledged': h.homeownerAcknowledged,
        'completed_at': h.completedAt?.toIso8601String(),
      };
}
