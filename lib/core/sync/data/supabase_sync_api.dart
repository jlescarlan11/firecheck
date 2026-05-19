import 'dart:io';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/sync_api.dart';
import 'package:firecheck/core/sync/domain/resolution_decision.dart';
import 'package:firecheck/core/sync/domain/submit_attribution_result.dart';
import 'package:firecheck/core/sync/domain/sync_outcome.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class SupabaseSyncApi implements SyncApi {
  SupabaseSyncApi(this._client);
  final SupabaseClient _client;
  static const _photosBucket = 'photos';

  @override
  Future<SyncOutcome> uploadSubmission(Map<String, dynamic> payload) async {
    try {
      await _client.rpc<dynamic>(
        'upload_submission_bundle',
        params: {'payload': payload},
      );
      return const Success();
    } on PostgrestException catch (e) {
      return _mapPostgrestException(e, payload);
    } on AuthException {
      return const AuthExpired();
    } on Object catch (e) {
      return TransientFailure(e.toString());
    }
  }

  @override
  Future<({SyncOutcome outcome, String? storagePath})> uploadPhotoFile({
    required String submissionId,
    required String photoId,
    required File file,
  }) async {
    final path = '$submissionId/$photoId.jpg';
    try {
      await _client.storage.from(_photosBucket).upload(
            path,
            file,
            fileOptions: const FileOptions(upsert: true),
          );
      return (outcome: const Success(), storagePath: path);
    } on StorageException catch (e) {
      return (outcome: _mapStorageException(e), storagePath: null);
    } on AuthException {
      return (outcome: const AuthExpired(), storagePath: null);
    } on Object catch (e) {
      return (outcome: TransientFailure(e.toString()), storagePath: null);
    }
  }

  @override
  Future<SyncOutcome> markPhotoUploaded({
    required String photoId,
    required String storagePath,
  }) async {
    try {
      // Only storage_path is server-side; upload_status is local-only per
      // master spec §6. The worker flips local photos.upload_status after
      // this returns Success.
      await _client.from('photos').update({
        'storage_path': storagePath,
      }).eq('id', photoId);
      return const Success();
    } on PostgrestException catch (e) {
      return _mapPostgrestException(e, null);
    } on AuthException {
      return const AuthExpired();
    } on Object catch (e) {
      return TransientFailure(e.toString());
    }
  }

  @override
  Future<SyncOutcome> uploadNewFeature(Feature feature) async {
    try {
      // Goes through upload_new_feature RPC because features.geometry is
      // PostGIS — PostgREST can't auto-convert raw GeoJSON. The RPC uses
      // ST_GeomFromGeoJSON server-side.
      await _client.rpc<dynamic>(
        'upload_new_feature',
        params: {
          'payload': {
            'id': feature.id,
            'assignment_id': feature.assignmentId,
            'feature_type': feature.featureType,
            'geometry_geojson': feature.geometryGeojson,
            'is_new': feature.isNew,
            'created_at': feature.createdAt.toIso8601String(),
          },
        },
      );
      return const Success();
    } on PostgrestException catch (e) {
      return _mapPostgrestException(e, null);
    } on AuthException {
      return const AuthExpired();
    } on Object catch (e) {
      return TransientFailure(e.toString());
    }
  }

  @override
  Future<SyncOutcome> uploadFeatureGeometryUpdate(
    FeatureGeometryRevision revision,
  ) async {
    try {
      await _client.rpc<dynamic>(
        'update_feature_geometry',
        params: {
          'p_revision_id': revision.id,
          'p_feature_id': revision.featureId,
          'p_prev_geojson': revision.prevGeojson,
          'p_new_geojson': revision.newGeojson,
          'p_edited_at': revision.editedAt.toIso8601String(),
          'p_override_reason': revision.overrideReason,
        },
      );
      return const Success();
    } on PostgrestException catch (e) {
      // P0001 + 'geometry_conflict' → server has newer geometry; permanent.
      // 42501 'forbidden' (RLS / auth) → permanent.
      // Other PG codes route through the standard mapper which routes 4xx
      // to PermanentFailure and 5xx/network to TransientFailure.
      if (e.code == 'P0001' || e.code == '42501') {
        return PermanentFailure('${e.code} ${e.message}');
      }
      return _mapPostgrestException(e, null);
    } on Object catch (e) {
      return TransientFailure(e.toString());
    }
  }

  SyncOutcome _mapPostgrestException(
    PostgrestException e,
    Map<String, dynamic>? submissionPayload,
  ) {
    // SQLSTATE 53300 → assignment_closed (raised by upload_submission_bundle)
    if (e.code == '53300' || e.message.contains('assignment_closed')) {
      final submission =
          submissionPayload?['submission'] as Map<String, dynamic>?;
      final assignmentId = submission?['assignment_id'] as String? ?? 'unknown';
      return AssignmentClosed(assignmentId);
    }
    final status = e.code;
    if (status == '401' || e.message.contains('JWT')) {
      return const AuthExpired();
    }
    if (status != null && status.startsWith('4')) {
      return PermanentFailure('${e.code} ${e.message}');
    }
    return TransientFailure('${e.code} ${e.message}');
  }

  SyncOutcome _mapStorageException(StorageException e) {
    final code = e.statusCode ?? '';
    if (code == '401') return const AuthExpired();
    if (code.startsWith('4')) return PermanentFailure('$code ${e.message}');
    return TransientFailure('$code ${e.message}');
  }

  // -------- Conflict-aware upload + resolution -------------------------

  @override
  Future<({SyncOutcome outcome, SubmitAttributionResult? result})>
      submitAttribution({
    required Map<String, dynamic> payload,
    String? baseVersionId,
  }) async {
    // The RPC expects base_version_id INSIDE the payload jsonb; tucking it
    // in here keeps the existing payload-builder unaware of conflict
    // semantics.
    final wrapped = Map<String, dynamic>.from(payload);
    if (baseVersionId != null) {
      wrapped['base_version_id'] = baseVersionId;
    }
    try {
      final raw = await _client.rpc<dynamic>(
        'submit_attribution_with_conflict_check',
        params: {'payload': wrapped},
      );
      final result = _parseAttributionResult(raw);
      if (result == null) {
        return (
          outcome: PermanentFailure('unexpected_response: $raw'),
          result: null,
        );
      }
      return (outcome: const Success(), result: result);
    } on PostgrestException catch (e) {
      return (outcome: _mapPostgrestException(e, payload), result: null);
    } on AuthException {
      return (outcome: const AuthExpired(), result: null);
    } on Object catch (e) {
      return (outcome: TransientFailure(e.toString()), result: null);
    }
  }

  @override
  Future<({SyncOutcome outcome, SubmitNewFeatureResult? result})>
      submitNewFeatureWithDedup(Map<String, dynamic> payload) async {
    try {
      final raw = await _client.rpc<dynamic>(
        'submit_new_feature_with_dedup_check',
        params: {'payload': payload},
      );
      final result = _parseNewFeatureResult(raw);
      if (result == null) {
        return (
          outcome: PermanentFailure('unexpected_response: $raw'),
          result: null,
        );
      }
      return (outcome: const Success(), result: result);
    } on PostgrestException catch (e) {
      return (outcome: _mapPostgrestException(e, null), result: null);
    } on AuthException {
      return (outcome: const AuthExpired(), result: null);
    } on Object catch (e) {
      return (outcome: TransientFailure(e.toString()), result: null);
    }
  }

  @override
  Future<SyncOutcome> resolveAttribution({
    required String pendingId,
    required AttributionDecision decision,
    String? resolutionNote,
  }) async {
    try {
      await _client.rpc<dynamic>(
        'resolve_attribution',
        params: {
          'pending_id': pendingId,
          'decision': decision.wire,
          'resolution_note': resolutionNote,
        },
      );
      return const Success();
    } on PostgrestException catch (e) {
      return _mapPostgrestException(e, null);
    } on AuthException {
      return const AuthExpired();
    } on Object catch (e) {
      return TransientFailure(e.toString());
    }
  }

  @override
  Future<SyncOutcome> resolveNewFeature({
    required String pendingId,
    required DedupDecision decision,
    String? resolutionNote,
  }) async {
    try {
      await _client.rpc<dynamic>(
        'resolve_new_feature',
        params: {
          'pending_id': pendingId,
          'decision': decision.wire,
          'resolution_note': resolutionNote,
        },
      );
      return const Success();
    } on PostgrestException catch (e) {
      return _mapPostgrestException(e, null);
    } on AuthException {
      return const AuthExpired();
    } on Object catch (e) {
      return TransientFailure(e.toString());
    }
  }

  SubmitAttributionResult? _parseAttributionResult(Object? raw) {
    if (raw is! Map) return null;
    final status = raw['status'];
    switch (status) {
      case 'committed':
        return AttributionCommitted(raw['submission_id'] as String);
      case 'agreed_skip':
        return AttributionAgreedSkip(raw['submission_id'] as String);
      case 'conflict':
        return AttributionConflict(
          pendingId: raw['pending_id'] as String,
          theirSubmissionId: raw['their_submission_id'] as String,
        );
      default:
        return null;
    }
  }

  SubmitNewFeatureResult? _parseNewFeatureResult(Object? raw) {
    if (raw is! Map) return null;
    final status = raw['status'];
    switch (status) {
      case 'committed':
        return NewFeatureCommitted(raw['feature_id'] as String);
      case 'dedup_pending':
        return NewFeatureDedupPending(
          pendingId: raw['pending_id'] as String,
          possibleDuplicateOf: raw['possible_duplicate_of'] as String,
        );
      default:
        return null;
    }
  }
}
