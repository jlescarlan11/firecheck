import 'dart:io';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/domain/resolution_decision.dart';
import 'package:firecheck/core/sync/domain/submit_attribution_result.dart';
import 'package:firecheck/core/sync/domain/sync_outcome.dart';

/// Network surface area required by SyncWorker. Real impl in
/// supabase_sync_api.dart; in-memory fake in fake_sync_api.dart.
abstract class SyncApi {
  /// Uploads a photo file to Storage, returning the storage_path on success.
  /// Encoded as a SyncOutcome to handle 401/409/permanent/transient uniformly.
  Future<({SyncOutcome outcome, String? storagePath})> uploadPhotoFile({
    required String submissionId,
    required String photoId,
    required File file,
  });

  Future<SyncOutcome> markPhotoUploaded({
    required String photoId,
    required String storagePath,
  });

  Future<SyncOutcome> uploadFeatureGeometryUpdate(FeatureGeometryRevision revision);

  // -------- Conflict-aware upload + resolution -------------------------

  /// Calls `submit_attribution_with_conflict_check`. Returns a structured
  /// result the worker can pattern-match on. Network / auth / closed-
  /// assignment errors come through `outcome`; structured results come
  /// through `result` (non-null when `outcome` is `Success`).
  Future<({SyncOutcome outcome, SubmitAttributionResult? result})>
      submitAttribution({
    required Map<String, dynamic> payload,
    String? baseVersionId,
  });

  /// Calls `submit_new_feature_with_dedup_check`. Same shape as
  /// `submitAttribution`.
  Future<({SyncOutcome outcome, SubmitNewFeatureResult? result})>
      submitNewFeatureWithDedup(Map<String, dynamic> payload);

  /// Calls `resolve_attribution(pending_id, decision, resolution_note?)`.
  Future<SyncOutcome> resolveAttribution({
    required String pendingId,
    required AttributionDecision decision,
    String? resolutionNote,
  });

  /// Calls `resolve_new_feature(pending_id, decision, resolution_note?)`.
  Future<SyncOutcome> resolveNewFeature({
    required String pendingId,
    required DedupDecision decision,
    String? resolutionNote,
  });
}
