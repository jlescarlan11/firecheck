import 'dart:io';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/sync_api.dart';
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
}
