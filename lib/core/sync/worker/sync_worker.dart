import 'dart:io';

import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:firecheck/core/sync/data/sync_api.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
import 'package:firecheck/core/sync/domain/retry_schedule.dart';
import 'package:firecheck/core/sync/domain/sync_entity_type.dart';
import 'package:firecheck/core/sync/domain/sync_outcome.dart';
import 'package:firecheck/core/sync/failure/assignment_lock_repository.dart';
import 'package:firecheck/core/sync/failure/pending_work_bundle.dart';
import 'package:firecheck/features/map/reshape/data/feature_geometry_revisions_repository.dart';
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
    try {
      while (true) {
        final assignmentRow =
            await db.select(db.assignments).getSingleOrNull();
        if (assignmentRow != null && assignmentRow.closedRemotely) return;

        final claimed = await jobs.claimUpToN(_maxConcurrent);
        if (claimed.isEmpty) return;
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

  Future<void> _applyOutcome(SyncJob job, SyncOutcome outcome) async {
    switch (outcome) {
      case Success():
        await jobs.markSuccess(job.id);
      case TransientFailure(:final error):
        final attempts = job.attempts + 1;
        final next = nextRetryAt(attempts);
        if (next == null) {
          await jobs.markDead(job.id, error: error, attempts: attempts);
        } else {
          await jobs.markPendingRetry(job.id,
              attempts: attempts, lastError: error, nextRetryAt: next,);
        }
      case PermanentFailure(:final error):
        await jobs.markDead(job.id, error: error, attempts: job.attempts + 1);
      case AuthExpired():
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
        // Bundle errors don't block lock state; surfaced in Phase 4b UI.
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
