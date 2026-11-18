import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_providers.dart'
    hide driveUploadNotifierProvider;
import 'package:firecheck/core/forms/field_requirements_providers.dart';
import 'package:firecheck/core/forms/form_definition.dart';
import 'package:firecheck/core/forms/form_definition_providers.dart';
import 'package:firecheck/core/forms/form_variant_providers.dart';
import 'package:firecheck/core/sync/domain/finalize_submission.dart';
import 'package:firecheck/core/sync/presentation/sync_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/review/data/review_repository.dart';
import 'package:firecheck/features/review/domain/drive_upload_state.dart';
import 'package:firecheck/features/review/domain/execute_assignment_upload_use_case.dart';
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/domain/review_validator.dart';
import 'package:firecheck/features/review/domain/upload_progress.dart';
import 'package:firecheck/features/review/presentation/drive_upload_notifier.dart';
import 'package:firecheck/features/review/presentation/sub/retry_dead_use_case.dart';
import 'package:firecheck/features/review/presentation/sub/start_upload_use_case.dart';
import 'package:firecheck/features/review/presentation/upload_progress_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  return ReviewRepository(ref.watch(appDatabaseProvider));
});

/// Snapshot of source data for the current assignment.
final reviewSourceProvider = StreamProvider<ReviewSourceData>((ref) async* {
  final assignment = ref.watch(currentAssignmentProvider).valueOrNull;
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
final assignmentJobsStreamProvider =
    StreamProvider.family<List<SyncJob>, String>((ref, assignmentId) async* {
  if (assignmentId.isEmpty) {
    yield const <SyncJob>[];
    return;
  }
  final db = ref.watch(appDatabaseProvider);
  yield* db
      .customSelect(
        '''
    SELECT j.* FROM sync_jobs j
    WHERE
      (j.entity_type IN ('submission', 'attribution_upload', 'attribution_resolve') AND j.entity_id IN (
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
      OR (j.entity_type IN ('new_feature', 'new_feature_upload', 'new_feature_resolve') AND j.entity_id IN (
        SELECT id FROM features WHERE assignment_id = ?
      ))
      OR (j.entity_type = 'feature_geometry_update' AND j.entity_id IN (
        SELECT g.id FROM feature_geometry_revisions g JOIN features f ON f.id=g.feature_id
        WHERE f.assignment_id=? AND g.sync_status NOT IN ('uploaded','discarded')
      ))
    ''',
        variables: [
          Variable.withString(assignmentId),
          Variable.withString(assignmentId),
          Variable.withString(assignmentId),
          Variable.withString(assignmentId),
        ],
        readsFrom: {
          db.syncJobs,
          db.submissions,
          db.features,
          db.photos,
          db.featureGeometryRevisions,
        },
      )
      .watch()
      .map((rows) => rows.map((r) => db.syncJobs.map(r.data)).toList());
});

final uploadProgressControllerProvider = StateNotifierProvider.family<
    UploadProgressController, UploadProgress, String>((ref, assignmentId) {
  // Bridge the StreamProvider's AsyncValue into a plain Stream so that
  // UploadProgressController receives List<SyncJob> events without
  // using the deprecated .stream accessor.
  final controller = StreamController<List<SyncJob>>();
  ref
    ..listen<AsyncValue<List<SyncJob>>>(
      assignmentJobsStreamProvider(assignmentId),
      (_, next) => next.whenData(controller.add),
      fireImmediately: true,
    )
    ..onDispose(controller.close);
  return UploadProgressController(jobsStream: controller.stream);
});

final assignmentUploadChangesProvider = StreamProvider.family<bool, String>(
  (ref, id) => id.isEmpty
      ? Stream.value(false)
      : ref.watch(assignmentRepositoryProvider).watchHasChangesToUpload(id),
);

/// Resolve saved finalized form versions from the source map's local history.
final reviewFormDefinitionsProvider =
    FutureProvider<Map<String, FormDefinition>>((ref) async {
  final sourceState = ref.watch(reviewSourceProvider);
  final source = sourceState.hasValue
      ? sourceState.requireValue
      : await ref.watch(reviewSourceProvider.future);
  final activeAssignment = ref.watch(currentAssignmentProvider).valueOrNull;
  if (activeAssignment != null &&
      source.assignmentId != null &&
      activeAssignment.id != source.assignmentId) {
    throw StateError(
      'The review snapshot belongs to a different map. Refresh the map before uploading.',
    );
  }
  final current = await ref.watch(currentFormDefinitionProvider.future);
  final definitions = <String, FormDefinition>{current.version: current};
  for (final sub in source.submissions.where(
    (sub) => const {'ready_to_upload', 'queued', 'uploaded'}
        .contains(sub.syncStatus),
  )) {
    if (definitions.containsKey(sub.formVersion)) continue;
    final assignmentId = source.assignmentId;
    if (assignmentId == null && sub.formVersion != 'legacy-v1') {
      throw StateError(
        'The saved form has no map identity. Refresh the map before uploading.',
      );
    }
    if (source.features.any(
      (feature) =>
          feature.id == sub.featureId && feature.assignmentId != assignmentId,
    )) {
      throw StateError(
        'The saved form does not belong to this map. Refresh the map before uploading.',
      );
    }
    definitions[sub.formVersion] = await loadAssignmentFormDefinition(
      assignmentId: assignmentId,
      requestedVersion: sub.formVersion,
    );
  }
  return definitions;
});

/// Composite ReviewState — source data + current upload progress.
final reviewStateProvider = Provider<AsyncValue<ReviewState>>((ref) {
  final sourceAsync = ref.watch(reviewSourceProvider);
  final requirements = ref.watch(fieldRequirementsConfigProvider);
  final definition = ref.watch(currentFormDefinitionProvider);
  final definitions = ref.watch(reviewFormDefinitionsProvider);
  final hidden = ref.watch(currentFormVariantProvider).hideBuildingFields;
  final id = ref.watch(currentAssignmentProvider).valueOrNull?.id ?? '';
  final progress = ref.watch(uploadProgressControllerProvider(id));
  final hasChanges = ref.watch(assignmentUploadChangesProvider(id));
  if (requirements.hasError) {
    return AsyncError(requirements.error!, requirements.stackTrace!);
  }
  if (definition.hasError) {
    return AsyncError(definition.error!, definition.stackTrace!);
  }
  if (definitions.hasError) {
    return AsyncError(definitions.error!, definitions.stackTrace!);
  }
  if (sourceAsync.isLoading ||
      requirements.isLoading ||
      definition.isLoading ||
      definitions.isLoading) {
    return const AsyncLoading();
  }
  return sourceAsync.whenData((source) {
    final base = buildReviewState(
      source,
      requirements: requirements.requireValue,
      definition: definition.requireValue,
      definitionsByVersion: definitions.requireValue,
      hiddenBuildingFields: hidden,
    );
    return ReviewState(
      assignmentId: source.assignmentId,
      hasChangesToUpload: hasChanges.valueOrNull ?? false,
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
    assignmentRepository: ref.watch(assignmentRepositoryProvider),
  );
  final assignment = ref.watch(currentAssignmentProvider).valueOrNull;
  if (assignment != null) notifier.initFromDb(assignment.id);
  return notifier;
});

final executeAssignmentUploadUseCaseProvider =
    Provider<ExecuteAssignmentUploadUseCase>((ref) {
  return ExecuteAssignmentUploadUseCase(
    sharedDb: ref.watch(appDatabaseProvider),
    assignmentRepository: ref.watch(assignmentRepositoryProvider),
    auditRepository: ref.watch(driveUploadAuditRepositoryProvider),
    startUploadUseCase: ref.watch(startUploadUseCaseProvider),
    enqueueAssignmentUseCase: ref.watch(enqueueAssignmentUseCaseProvider),
    driveUploadRepository: ref.watch(driveUploadRepoProvider),
    driveUploadWorker: ref.watch(driveUploadWorkerProvider),
    finalizeAssignmentUploadUseCase:
        ref.watch(finalizeAssignmentUploadUseCaseProvider),
    progressController: ref.watch(
      uploadProgressControllerProvider(
        ref.watch(currentAssignmentProvider).valueOrNull?.id ?? '',
      ).notifier,
    ),
  );
});

final sharedMapModeProvider = StreamProvider<bool>((ref) {
  final assignment = ref.watch(currentAssignmentProvider).valueOrNull;
  final account = ref.watch(currentUserIdProvider);
  if (assignment == null || account == null) return Stream.value(false);
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.sharedMapCursors)
        ..where(
          (t) =>
              t.assignmentId.equals(assignment.id) &
              t.accountId.equals(account),
        ))
      .watchSingleOrNull()
      .map((c) => c != null);
});
