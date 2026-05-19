import 'dart:io';

import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:firecheck/core/sync/data/sync_api.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
import 'package:firecheck/core/sync/domain/resolution_decision.dart';
import 'package:firecheck/core/sync/domain/retry_schedule.dart';
import 'package:firecheck/core/sync/domain/submission_sync_status.dart';
import 'package:firecheck/core/sync/domain/submit_attribution_result.dart';
import 'package:firecheck/core/sync/domain/sync_entity_type.dart';
import 'package:firecheck/core/sync/domain/sync_outcome.dart';
import 'package:firecheck/core/sync/failure/assignment_lock_repository.dart';
import 'package:firecheck/core/sync/failure/pending_work_bundle.dart';
import 'package:firecheck/features/map/geometry_editor/data/feature_geometry_revisions_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class SyncWorker {
  SyncWorker({
    required this.api,
    required this.jobs,
    required this.payload,
    required this.lock,
    required this.db,
    this.bundle,
    SupabaseClient? supabaseClient,
    Future<bool> Function()? refreshSession,
  })  : _supabaseClient = supabaseClient,
        _refreshSession = refreshSession;

  final SyncApi api;
  final SyncJobsRepository jobs;
  final SubmissionPayloadBuilder payload;
  final AssignmentLockRepository lock;
  final AppDatabase db;
  final PendingWorkBundle? bundle;
  final SupabaseClient? _supabaseClient;
  final Future<bool> Function()? _refreshSession;

  static const _maxConcurrent = 3;
  bool _running = false;

  Future<void> drain() async {
    if (_running) return;
    _running = true;
    debugPrint('[StartUpload] drain started');
    try {
      while (true) {
        // limit(1) guards against StateError when >1 assignment row exists.
        final assignmentRow =
            await (db.select(db.assignments)..limit(1)).getSingleOrNull();
        if (assignmentRow != null && assignmentRow.closedRemotely) {
          debugPrint('[StartUpload] assignment closed remotely — halting drain');
          return;
        }

        final claimed = await jobs.claimUpToN(_maxConcurrent);
        if (claimed.isEmpty) {
          debugPrint('[StartUpload] no claimable jobs — drain complete');
          return;
        }
        debugPrint(
          '[StartUpload] claimed ${claimed.length} job(s): '
          '${claimed.map((j) => '${j.entityType}:${j.id.substring(0, 8)}').join(', ')}',
        );
        await Future.wait(claimed.map(_processOne));
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _processOne(SyncJob job) async {
    final outcome = await _execute(job);
    await _applyOutcome(job, outcome);
  }

  Future<SyncOutcome> _execute(SyncJob job) async {
    try {
      switch (job.entityType) {
        case SyncEntityType.submission:
          return await _executeSubmission(job.entityId);
        case SyncEntityType.photo:
          return await _executePhoto(job.entityId);
        case SyncEntityType.newFeature:
          return await _executeNewFeature(job.entityId);
        case SyncEntityType.featureGeometryUpdate:
          return await _executeFeatureGeometryUpdate(job.entityId);
        case SyncEntityType.attributionUpload:
          return await _executeAttributionUpload(job.entityId);
        case SyncEntityType.attributionResolve:
          return await _executeAttributionResolve(job.entityId);
        case SyncEntityType.newFeatureUpload:
          return await _executeNewFeatureUpload(job.entityId);
        case SyncEntityType.newFeatureResolve:
          return await _executeNewFeatureResolve(job.entityId);
        default:
          return PermanentFailure('unknown entity_type: ${job.entityType}');
      }
    } on Object catch (e) {
      return TransientFailure(e.toString());
    }
  }

  Future<SyncOutcome> _executeSubmission(String submissionId) async {
    final json = await payload.build(submissionId);
    final outcome = await api.uploadSubmission(json);
    if (outcome is Success) {
      await (db.update(db.submissions)
            ..where((t) => t.id.equals(submissionId)))
          .write(const SubmissionsCompanion(syncStatus: Value('uploaded')));
    }
    return outcome;
  }

  Future<SyncOutcome> _executePhoto(String photoId) async {
    final photo = await (db.select(db.photos)
          ..where((t) => t.id.equals(photoId)))
        .getSingle();
    final file = File(photo.localPath);
    if (!file.existsSync()) {
      return const PermanentFailure('photo file missing');
    }
    final upload = await api.uploadPhotoFile(
      submissionId: photo.submissionId,
      photoId: photoId,
      file: file,
    );
    if (upload.outcome is! Success || upload.storagePath == null) {
      return upload.outcome;
    }
    final mark = await api.markPhotoUploaded(
      photoId: photoId,
      storagePath: upload.storagePath!,
    );
    if (mark is Success) {
      await (db.update(db.photos)..where((t) => t.id.equals(photoId))).write(
        PhotosCompanion(
          storagePath: Value(upload.storagePath),
          uploadStatus: const Value('uploaded'),
        ),
      );
    }
    return mark;
  }

  Future<SyncOutcome> _executeNewFeature(String featureId) async {
    final feature = await (db.select(db.features)
          ..where((t) => t.id.equals(featureId)))
        .getSingle();
    return api.uploadNewFeature(feature);
  }

  Future<SyncOutcome> _executeFeatureGeometryUpdate(String revisionId) async {
    final repo = FeatureGeometryRevisionsRepository(db);
    final rev = await repo.getById(revisionId);
    if (rev == null) {
      return const PermanentFailure('revision missing');
    }
    final outcome = await api.uploadFeatureGeometryUpdate(rev);
    if (outcome is Success) {
      await repo.markSynced(rev.id);
    } else if (outcome is PermanentFailure) {
      await repo.markFailed(rev.id);
    }
    return outcome;
  }

  /// Calls `submit_attribution_with_conflict_check`. Routes the three
  /// possible structured results to local state transitions:
  ///   - committed     → submission marked uploaded (same as legacy path)
  ///   - agreed_skip   → server already has identical canonical; local
  ///                     row is effectively withdrawn (orphan cleanup
  ///                     handled separately)
  ///   - conflict      → submission parked in awaiting_user_resolution
  ///                     with pendingTheirsId set; review UI takes over
  Future<SyncOutcome> _executeAttributionUpload(String submissionId) async {
    final sub = await (db.select(db.submissions)
          ..where((t) => t.id.equals(submissionId)))
        .getSingleOrNull();
    if (sub == null) {
      return const PermanentFailure('submission missing');
    }
    final json = await payload.build(submissionId);
    final response = await api.submitAttribution(payload: json);
    if (response.outcome is! Success) {
      return response.outcome;
    }
    final result = response.result!;
    switch (result) {
      case AttributionCommitted():
        await (db.update(db.submissions)
              ..where((t) => t.id.equals(submissionId)))
            .write(
          const SubmissionsCompanion(
            syncStatus: Value(SubmissionSyncStatus.uploaded),
            pendingTheirsId: Value(null),
          ),
        );
      case AttributionAgreedSkip():
        // Server's canonical wins identical values; our row is a duplicate.
        await (db.update(db.submissions)
              ..where((t) => t.id.equals(submissionId)))
            .write(
          const SubmissionsCompanion(
            syncStatus: Value(SubmissionSyncStatus.withdrawn),
            pendingTheirsId: Value(null),
          ),
        );
      case AttributionConflict(:final theirSubmissionId):
        await (db.update(db.submissions)
              ..where((t) => t.id.equals(submissionId)))
            .write(
          SubmissionsCompanion(
            syncStatus: const Value(SubmissionSyncStatus.awaitingUserResolution),
            pendingTheirsId: Value(theirSubmissionId),
          ),
        );
    }
    return const Success();
  }

  /// Calls `submit_new_feature_with_dedup_check`. dedup_pending leaves the
  /// row visible (the proximity trigger has already inserted it) and the
  /// review UI surfaces it; review then dispatches a
  /// `newFeatureResolve` job.
  Future<SyncOutcome> _executeNewFeatureUpload(String featureId) async {
    final feature = await (db.select(db.features)
          ..where((t) => t.id.equals(featureId)))
        .getSingleOrNull();
    if (feature == null) {
      return const PermanentFailure('feature missing');
    }
    final payload = <String, dynamic>{
      'id': feature.id,
      'assignment_id': feature.assignmentId,
      'feature_type': feature.featureType,
      'geometry_geojson': feature.geometryGeojson,
      'is_new': feature.isNew,
      'created_at': feature.createdAt.toIso8601String(),
    };
    final response = await api.submitNewFeatureWithDedup(payload);
    return response.outcome;
  }

  /// Reads the queued decision out of `pending_resolutions`, calls
  /// `resolve_attribution`, then updates local sync_status + clears the
  /// queued row.
  Future<SyncOutcome> _executeAttributionResolve(String submissionId) async {
    final res = await (db.select(db.pendingResolutions)
          ..where((t) =>
              t.targetId.equals(submissionId) & t.kind.equals('attribution'),))
        .getSingleOrNull();
    if (res == null) {
      return const PermanentFailure('no queued resolution');
    }
    final decision = _attributionDecisionFromWire(res.decision);
    if (decision == null) {
      return PermanentFailure('invalid_decision: ${res.decision}');
    }
    final outcome = await api.resolveAttribution(
      pendingId: submissionId,
      decision: decision,
      resolutionNote: res.resolutionNote,
    );
    if (outcome is! Success) return outcome;

    await db.transaction(() async {
      await (db.update(db.submissions)
            ..where((t) => t.id.equals(submissionId)))
          .write(
        SubmissionsCompanion(
          syncStatus: Value(
            decision == AttributionDecision.forceOverwrite
                ? SubmissionSyncStatus.uploaded
                : SubmissionSyncStatus.withdrawn,
          ),
          pendingTheirsId: const Value(null),
        ),
      );
      await (db.delete(db.pendingResolutions)
            ..where((t) =>
                t.targetId.equals(submissionId) &
                t.kind.equals('attribution'),))
          .go();
    });
    return const Success();
  }

  Future<SyncOutcome> _executeNewFeatureResolve(String featureId) async {
    final res = await (db.select(db.pendingResolutions)
          ..where((t) =>
              t.targetId.equals(featureId) & t.kind.equals('new_feature'),))
        .getSingleOrNull();
    if (res == null) {
      return const PermanentFailure('no queued resolution');
    }
    final decision = _dedupDecisionFromWire(res.decision);
    if (decision == null) {
      return PermanentFailure('invalid_decision: ${res.decision}');
    }
    final outcome = await api.resolveNewFeature(
      pendingId: featureId,
      decision: decision,
      resolutionNote: res.resolutionNote,
    );
    if (outcome is! Success) return outcome;

    await (db.delete(db.pendingResolutions)
          ..where((t) =>
              t.targetId.equals(featureId) & t.kind.equals('new_feature'),))
        .go();
    return const Success();
  }

  AttributionDecision? _attributionDecisionFromWire(String wire) {
    for (final d in AttributionDecision.values) {
      if (d.wire == wire) return d;
    }
    return null;
  }

  DedupDecision? _dedupDecisionFromWire(String wire) {
    for (final d in DedupDecision.values) {
      if (d.wire == wire) return d;
    }
    return null;
  }

  Future<void> _applyOutcome(SyncJob job, SyncOutcome outcome) async {
    switch (outcome) {
      case Success():
        debugPrint(
          '[StartUpload] ✓ ${job.entityType}:${job.id.substring(0, 8)} succeeded',
        );
        await jobs.markSuccess(job.id);
      case TransientFailure(:final error):
        final attempts = job.attempts + 1;
        final next = nextRetryAt(attempts);
        if (next == null) {
          debugPrint(
            '[StartUpload] ✗ ${job.entityType}:${job.id.substring(0, 8)} '
            'dead after $attempts attempts — $error',
          );
          await jobs.markDead(job.id, error: error, attempts: attempts);
        } else {
          debugPrint(
            '[StartUpload] ~ ${job.entityType}:${job.id.substring(0, 8)} '
            'transient (attempt $attempts), retry at $next — $error',
          );
          await jobs.markPendingRetry(job.id,
              attempts: attempts, lastError: error, nextRetryAt: next,);
        }
      case PermanentFailure(:final error):
        debugPrint(
          '[StartUpload] ✗ ${job.entityType}:${job.id.substring(0, 8)} '
          'permanent failure — $error',
        );
        await jobs.markDead(job.id, error: error, attempts: job.attempts + 1);
      case AuthExpired():
        debugPrint(
          '[StartUpload] ! ${job.entityType}:${job.id.substring(0, 8)} '
          'auth expired — attempting refresh',
        );
        await _handleAuthExpired(job);
      case AssignmentClosed(:final assignmentId):
        await _handleAssignmentClosed(job, assignmentId);
    }
  }

  Future<bool> _defaultRefresh() async {
    final client = _supabaseClient ?? Supabase.instance.client;
    final res = await client.auth.refreshSession();
    return res.session != null;
  }

  Future<void> _handleAuthExpired(SyncJob job) async {
    final refresh = _refreshSession ?? _defaultRefresh;
    bool ok;
    try {
      ok = await refresh();
    } on Object {
      ok = false;
    }
    if (!ok) {
      await _applyOutcome(job, const TransientFailure('auth refresh failed'));
      return;
    }
    final retry = await _execute(job);
    await _applyOutcome(
        job, retry is AuthExpired ? const TransientFailure('repeat 401') : retry,);
  }

  Future<void> _handleAssignmentClosed(
      SyncJob job, String assignmentId,) async {
    await lock.markClosed(assignmentId);
    if (bundle != null) {
      try {
        await bundle!.exportFor(assignmentId);
      } on Object {
        // Bundle errors don't block lock state; surfaced in the UI separately.
      }
    }
    // Job goes back to pending so a future drain (after lock clears) can retry.
    await jobs.markPendingRetry(
      job.id,
      attempts: job.attempts,
      lastError: '409 assignment_closed',
      nextRetryAt: null,
    );
  }
}
