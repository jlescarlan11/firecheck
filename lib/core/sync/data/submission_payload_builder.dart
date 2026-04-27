import 'dart:convert';

import 'package:firecheck/core/db/database.dart';

class SubmissionPayloadBuilder {
  SubmissionPayloadBuilder(this._db);
  final AppDatabase _db;

  /// Builds the payload for `upload_submission_bundle` RPC. The remote
  /// schema differs from local Drift in two ways:
  ///   - column names drop the `_json` suffix (kaayusan, fire_load, etc.)
  ///   - jsonb-shaped columns expect native JSON values, not text strings
  /// We decode the local jsonb-as-text columns here so the RPC sees native
  /// arrays/objects.
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
        // Supabase expects a uuid; null is acceptable. Phase 2 placeholder
        // 'admin' fails the uuid cast — coerce to null until real auth wires
        // submittedBy to Supabase.instance.client.auth.currentUser.id.
        'submitted_by': _asUuidOrNull(s.submittedBy),
        'does_not_exist': s.doesNotExist,
        'remarks': s.remarks,
        'override_reason': s.overrideReason,
        'created_at': s.createdAt.toIso8601String(),
        'updated_at': s.updatedAt.toIso8601String(),
        // sync_status is local-only per master spec §6 — not sent.
      };

  static final _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  String? _asUuidOrNull(String? raw) =>
      raw != null && _uuidRegex.hasMatch(raw) ? raw : null;

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
        'fire_fighting_facilities':
            _decodeJsonArray(b.fireFightingFacilitiesJson),
        'fire_load': _decodeJsonArray(b.fireLoadJson),
      };

  Map<String, dynamic> _roadToJson(RoadAttribute r) => {
        'submission_id': r.submissionId,
        'is_bridge': r.isBridge,
        'road_name': r.roadName,
        'width_meters': r.widthMeters,
        'road_features': _decodeJsonArray(r.roadFeaturesJson),
        'others_description': r.othersDescription,
      };

  Map<String, dynamic> _householdToJson(HouseholdSurvey h) => {
        'submission_id': h.submissionId,
        'construction_details': _decodeJsonObject(h.constructionDetailsJson),
        'kaayusan': _decodeJsonObject(h.kaayusanJson),
        'koneksyong_elektrikal': _decodeJsonObject(h.koneksyongElektrikalJson),
        'kusina': _decodeJsonObject(h.kusinaJson),
        'daanan_o_labasan': _decodeJsonObject(h.daananOLabasanJson),
        'lebel_ng_kahinaan': h.lebelNgKahinaan,
        'safety_suggestions': h.safetySuggestions,
        'homeowner_acknowledged': h.homeownerAcknowledged,
        'completed_at': h.completedAt?.toIso8601String(),
      };

  List<dynamic> _decodeJsonArray(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : const [];
    } on Object {
      return const [];
    }
  }

  Map<String, dynamic> _decodeJsonObject(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on Object {
      return const {};
    }
  }
}
