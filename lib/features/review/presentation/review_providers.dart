import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/domain/finalize_submission.dart';
import 'package:firecheck/core/sync/presentation/sync_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/review/domain/drive_upload_state.dart';
import 'package:firecheck/features/review/presentation/drive_upload_notifier.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/review/data/review_repository.dart';
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/domain/review_validator.dart';
import 'package:firecheck/features/review/domain/upload_progress.dart';
import 'package:firecheck/features/review/presentation/sub/retry_dead_use_case.dart';
import 'package:firecheck/features/review/presentation/sub/start_upload_use_case.dart';
import 'package:firecheck/features/review/presentation/upload_progress_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  return ReviewRepository(ref.watch(appDatabaseProvider));
});

/// Snapshot of source data for the current assignment.
final reviewSourceProvider = StreamProvider<ReviewSourceData>((ref) async* {
  final assignment =
      await ref.watch(assignmentRepositoryProvider).getCurrentAssignment();
  if (assignment == null) {
    yield const ReviewSourceData(
      features: [],
      submissions: [],
      buildingAttrs: [],
      roadAttrs: [],
      householdSurveys: [],
      photoCountsBySubmission: {},
      deadJobs: [],
    );
    return;
  }
  yield* ref.watch(reviewRepositoryProvider).streamForAssignment(assignment.id);
});

/// Stream of sync_jobs for the current assignment, used by the upload
/// progress controller.
final assignmentJobsStreamProvider = StreamProvider<List<SyncJob>>((ref) async* {
  final assignment =
      await ref.watch(assignmentRepositoryProvider).getCurrentAssignment();
  if (assignment == null) {
    yield const <SyncJob>[];
    return;
  }
  final db = ref.watch(appDatabaseProvider);
  yield* db.customSelect(
    '''
    SELECT j.* FROM sync_jobs j
    WHERE
      (j.entity_type = 'submission' AND j.entity_id IN (
        SELECT s.id FROM submissions s
        JOIN features f ON f.id = s.feature_id
        WHERE f.assignment_id = ?
      ))
      OR (j.entity_type = 'photo' AND j.entity_id IN (
        SELECT p.id FROM photos p
        JOIN submissions s ON s.id = p.submission_id
        JOIN features f ON f.id = s.feature_id
        WHERE f.assignment_id = ?
      ))
      OR (j.entity_type = 'new_feature' AND j.entity_id IN (
        SELECT id FROM features WHERE assignment_id = ?
      ))
    ''',
    variables: [
      Variable.withString(assignment.id),
      Variable.withString(assignment.id),
      Variable.withString(assignment.id),
    ],
    readsFrom: {db.syncJobs, db.submissions, db.features, db.photos},
  ).watch().map((rows) => rows.map((r) => db.syncJobs.map(r.data)).toList());
});

final uploadProgressControllerProvider =
    StateNotifierProvider<UploadProgressController, UploadProgress>((ref) {
  // Bridge the StreamProvider's AsyncValue into a plain Stream so that
  // UploadProgressController receives List<SyncJob> events without
  // using the deprecated .stream accessor.
  final controller = StreamController<List<SyncJob>>();
  ref
    ..listen<AsyncValue<List<SyncJob>>>(
      assignmentJobsStreamProvider,
      (_, next) => next.whenData(controller.add),
    )
    ..onDispose(controller.close);
  return UploadProgressController(jobsStream: controller.stream);
});

/// Composite ReviewState — source data + current upload progress.
final reviewStateProvider = Provider<AsyncValue<ReviewState>>((ref) {
  final sourceAsync = ref.watch(reviewSourceProvider);
  final progress = ref.watch(uploadProgressControllerProvider);
  return sourceAsync.whenData((source) {
    final base = buildReviewState(source);
    return ReviewState(
      summary: base.summary,
      warnings: base.warnings,
      blockers: base.blockers,
      deadJobs: base.deadJobs,
      upload: progress,
    );
  });
});

final retryDeadUseCaseProvider = Provider<RetryDeadUseCase>((ref) {
  final controller = ref.watch(syncControllerProvider);
  return RetryDeadUseCase(
    db: ref.watch(appDatabaseProvider),
    triggerNow: controller.triggerNow,
  );
});

final startUploadUseCaseProvider = Provider<StartUploadUseCase>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final controller = ref.watch(syncControllerProvider);
  return StartUploadUseCase(
    db: db,
    finalize: FinalizeSubmissionUseCase(db),
    triggerNow: controller.triggerNow,
  );
});

final driveUploadNotifierProvider =
    StateNotifierProvider<DriveUploadNotifier, DriveUploadState>((ref) {
  final notifier = DriveUploadNotifier(
    driveApi: ref.watch(driveApiProvider),
    assignmentRepository: ref.watch(assignmentRepositoryProvider),
  );
  ref
      .watch(assignmentRepositoryProvider)
      .getCurrentAssignment()
      .then((assignment) {
    if (assignment != null) {
      notifier.initFromDb(assignment.id, assignment.enumeratorId);
    }
  });
  return notifier;
});
