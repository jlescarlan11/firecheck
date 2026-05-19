import 'dart:io';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/sync_api.dart';
import 'package:firecheck/core/sync/domain/resolution_decision.dart';
import 'package:firecheck/core/sync/domain/submit_attribution_result.dart';
import 'package:firecheck/core/sync/domain/sync_outcome.dart';

/// Test double whose responses are seeded by the test. Each method consumes
/// one queued outcome per call; if no responses are queued, returns Success.
class FakeSyncApi implements SyncApi {
  final List<SyncOutcome> _submissionResponses = [];
  final List<SyncOutcome> _photoUploadResponses = [];
  final List<SyncOutcome> _photoMarkResponses = [];
  final List<SyncOutcome> _newFeatureResponses = [];
  final List<SyncOutcome> _featureGeometryUpdateResponses = [];

  /// Records of every call, in order, for assertions.
  final List<Map<String, dynamic>> uploadSubmissionCalls = [];
  final List<({String submissionId, String photoId})> uploadPhotoFileCalls =
      [];
  final List<({String photoId, String storagePath})> markPhotoUploadedCalls =
      [];
  final List<Feature> uploadNewFeatureCalls = [];
  final List<FeatureGeometryRevision> uploadFeatureGeometryUpdateCalls = [];

  /// Configure the next outcome each method should return.
  void enqueueSubmission(SyncOutcome o) => _submissionResponses.add(o);
  void enqueuePhotoUpload(SyncOutcome o) => _photoUploadResponses.add(o);
  void enqueuePhotoMark(SyncOutcome o) => _photoMarkResponses.add(o);
  void enqueueNewFeature(SyncOutcome o) => _newFeatureResponses.add(o);
  void enqueueFeatureGeometryUpdate(SyncOutcome o) =>
      _featureGeometryUpdateResponses.add(o);

  SyncOutcome _next(List<SyncOutcome> q) =>
      q.isEmpty ? const Success() : q.removeAt(0);

  @override
  Future<SyncOutcome> uploadSubmission(Map<String, dynamic> payload) async {
    uploadSubmissionCalls.add(payload);
    return _next(_submissionResponses);
  }

  @override
  Future<({SyncOutcome outcome, String? storagePath})> uploadPhotoFile({
    required String submissionId,
    required String photoId,
    required File file,
  }) async {
    uploadPhotoFileCalls.add((submissionId: submissionId, photoId: photoId));
    final outcome = _next(_photoUploadResponses);
    final path = outcome is Success ? '$submissionId/$photoId.jpg' : null;
    return (outcome: outcome, storagePath: path);
  }

  @override
  Future<SyncOutcome> markPhotoUploaded({
    required String photoId,
    required String storagePath,
  }) async {
    markPhotoUploadedCalls.add((photoId: photoId, storagePath: storagePath));
    return _next(_photoMarkResponses);
  }

  @override
  Future<SyncOutcome> uploadNewFeature(Feature feature) async {
    uploadNewFeatureCalls.add(feature);
    return _next(_newFeatureResponses);
  }

  @override
  Future<SyncOutcome> uploadFeatureGeometryUpdate(
    FeatureGeometryRevision revision,
  ) async {
    uploadFeatureGeometryUpdateCalls.add(revision);
    return _next(_featureGeometryUpdateResponses);
  }

  // -------- Conflict-aware upload + resolution -------------------------

  final List<
      ({SyncOutcome outcome, SubmitAttributionResult? result})>
      _submitAttributionResponses = [];
  final List<
      ({SyncOutcome outcome, SubmitNewFeatureResult? result})>
      _submitNewFeatureResponses = [];
  final List<SyncOutcome> _resolveAttributionResponses = [];
  final List<SyncOutcome> _resolveNewFeatureResponses = [];

  final List<({Map<String, dynamic> payload, String? baseVersionId})>
      submitAttributionCalls = [];
  final List<Map<String, dynamic>> submitNewFeatureCalls = [];
  final List<({String pendingId, AttributionDecision decision, String? note})>
      resolveAttributionCalls = [];
  final List<({String pendingId, DedupDecision decision, String? note})>
      resolveNewFeatureCalls = [];

  void enqueueSubmitAttribution({
    SyncOutcome outcome = const Success(),
    SubmitAttributionResult? result,
  }) {
    _submitAttributionResponses.add((outcome: outcome, result: result));
  }

  void enqueueSubmitNewFeature({
    SyncOutcome outcome = const Success(),
    SubmitNewFeatureResult? result,
  }) {
    _submitNewFeatureResponses.add((outcome: outcome, result: result));
  }

  void enqueueResolveAttribution(SyncOutcome o) =>
      _resolveAttributionResponses.add(o);
  void enqueueResolveNewFeature(SyncOutcome o) =>
      _resolveNewFeatureResponses.add(o);

  @override
  Future<({SyncOutcome outcome, SubmitAttributionResult? result})>
      submitAttribution({
    required Map<String, dynamic> payload,
    String? baseVersionId,
  }) async {
    submitAttributionCalls
        .add((payload: payload, baseVersionId: baseVersionId));
    String defaultId() =>
        (payload['submission'] as Map<String, dynamic>)['id'] as String;

    if (_submitAttributionResponses.isEmpty) {
      // Default: committed with the payload's submission id.
      return (
        outcome: const Success(),
        result: AttributionCommitted(defaultId()),
      );
    }
    final next = _submitAttributionResponses.removeAt(0);
    if (next.outcome is Success && next.result == null) {
      // Enqueued shorthand: a bare Success with no explicit result still
      // means "committed with the payload's id".
      return (
        outcome: next.outcome,
        result: AttributionCommitted(defaultId()),
      );
    }
    return next;
  }

  @override
  Future<({SyncOutcome outcome, SubmitNewFeatureResult? result})>
      submitNewFeatureWithDedup(Map<String, dynamic> payload) async {
    submitNewFeatureCalls.add(payload);
    if (_submitNewFeatureResponses.isEmpty) {
      final id = payload['id'] as String;
      return (outcome: const Success(), result: NewFeatureCommitted(id));
    }
    return _submitNewFeatureResponses.removeAt(0);
  }

  @override
  Future<SyncOutcome> resolveAttribution({
    required String pendingId,
    required AttributionDecision decision,
    String? resolutionNote,
  }) async {
    resolveAttributionCalls.add((
      pendingId: pendingId,
      decision: decision,
      note: resolutionNote,
    ));
    return _next(_resolveAttributionResponses);
  }

  @override
  Future<SyncOutcome> resolveNewFeature({
    required String pendingId,
    required DedupDecision decision,
    String? resolutionNote,
  }) async {
    resolveNewFeatureCalls.add((
      pendingId: pendingId,
      decision: decision,
      note: resolutionNote,
    ));
    return _next(_resolveNewFeatureResponses);
  }
}
