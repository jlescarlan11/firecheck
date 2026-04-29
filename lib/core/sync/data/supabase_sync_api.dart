import 'dart:io';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/sync_api.dart';
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
}
