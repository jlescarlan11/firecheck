import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/fake_sync_api.dart';
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
import 'package:firecheck/core/sync/domain/finalize_submission.dart';
import 'package:firecheck/core/sync/domain/submit_attribution_result.dart';
import 'package:firecheck/core/sync/domain/sync_outcome.dart';
import 'package:firecheck/core/sync/failure/assignment_lock_repository.dart';
import 'package:firecheck/core/sync/worker/sync_worker.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:firecheck/features/map/data/feature_repository.dart';
import 'package:firecheck/features/review/presentation/sub/retry_dead_use_case.dart';
import 'package:firecheck/features/survey/building_form/data/building_attributes_repository.dart';
import 'package:firecheck/features/survey/building_form/data/submission_repository.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form_notifier.dart';
import 'package:firecheck/features/survey/olp_survey/data/household_survey_repository.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_form_state.dart';
import 'package:firecheck/features/survey/road_form/data/road_attributes_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/survey_integration_fixture.dart';

class HeldReceiptApi extends FakeSyncApi {
  final received = Completer<void>();
  final release = Completer<void>();
  @override
  Future<({SyncOutcome outcome, SubmitAttributionResult? result})>
      submitAttribution({
    required Map<String, dynamic> payload,
    String? baseVersionId,
  }) async {
    received.complete();
    await release.future;
    return super
        .submitAttribution(payload: payload, baseVersionId: baseVersionId);
  }
}

void main() {
  late SurveyIntegrationFixture h;
  setUp(() async {
    h = await SurveyIntegrationFixture.create();
    await seedIntegrationSurvey(h.db);
  });
  tearDown(() async {
    await h.db.close();
    await h.directory.delete(recursive: true);
  });
  SyncWorker worker(FakeSyncApi api) => SyncWorker(
        api: api,
        jobs: SyncJobsRepository(h.db, ownerId: integrationActor),
        payload: SubmissionPayloadBuilder(h.db),
        lock: AssignmentLockRepository(h.db),
        db: h.db,
      );

  test(
      'intentional persisted edit gets a new frozen operation; duplicate finalize does not',
      () async {
    final finalize = FinalizeSubmissionUseCase(h.db);
    await finalize.execute('s1');
    await worker(h.api).drain();
    final first = await h.db.select(h.db.syncJobs).getSingle();
    await BuildingAttributesRepository(h.db)
        .upsertForSubmission(submissionId: 's1', buildingName: 'Revision two');
    await SubmissionRepository(h.db).markStatus('s1', 'ready_to_upload');
    await finalize.execute('s1');
    await finalize.execute('s1');
    final jobs = await h.db.select(h.db.syncJobs).get();
    expect(jobs, hasLength(2));
    expect(jobs.first.payloadJson, first.payloadJson);
    await worker(h.api).drain();
    expect(h.api.submitAttributionCalls, hasLength(2));
    expect(
      h.api.submitAttributionCalls.last.payload['operation_id'],
      isNot(first.id),
    );
  });

  test(
      'persisting changed accepted form marks it editable pending; no-op flush preserves upload',
      () async {
    await BuildingAttributesRepository(h.db)
        .upsertForSubmission(submissionId: 's1', buildingName: 'Initial');
    final n = BuildingFormNotifier(
      submissionId: 's1',
      featureId: 'f1',
      submissionRepo: SubmissionRepository(h.db),
      attrsRepo: BuildingAttributesRepository(h.db),
      featureRepo: FeatureRepository(h.db),
    );
    await BuildingAttributesRepository(h.db).watchForSubmission('s1').first;
    await FinalizeSubmissionUseCase(h.db).execute('s1');
    await worker(h.api).drain();
    await n.flushNow();
    expect(
      (await h.db.select(h.db.submissions).getSingle()).syncStatus,
      'uploaded',
    );
    n.update((s) => s.copyWith(buildingName: 'Changed'));
    await n.flushNow();
    expect(
      (await h.db.select(h.db.submissions).getSingle()).syncStatus,
      'in_progress',
    );
    n.dispose();
  });

  for (final kind in ['road', 'household', 'override']) {
    test(
        'persisted $kind edits mark accepted survey pending without changing no-op timestamps',
        () async {
      await SubmissionRepository(h.db).markStatus('s1', 'uploaded');
      if (kind == 'road') {
        await RoadAttributesRepository(h.db).upsertForSubmission(
          's1',
          RoadAttributesCompanion.insert(
            submissionId: 's1',
            roadName: const Value('Changed'),
          ),
        );
      } else if (kind == 'household') {
        await HouseholdSurveyRepository(h.db).upsertForSubmission(
          state: const OlpFormState(
            submissionId: 's1',
            homeownerAcknowledged: true,
          ),
          lebelNgKahinaan: 'Low',
          safetySuggestionKeys: const [],
        );
      } else {
        await SubmissionRepository(h.db).updateOverrideReason('s1', 'Verified');
      }
      expect(
        (await h.db.select(h.db.submissions).getSingle()).syncStatus,
        'in_progress',
      );
    });
  }

  test(
      'legacy review sees a new ready revision even in the confirmation second',
      () async {
    final sameSecond = DateTime.utc(2026);
    await h.db
        .update(h.db.assignments)
        .write(AssignmentsCompanion(driveUploadConfirmedAt: Value(sameSecond)));
    await h.db.update(h.db.submissions).write(
          SubmissionsCompanion(
            syncStatus: const Value('ready_to_upload'),
            updatedAt: Value(sameSecond),
          ),
        );
    expect(
      await AssignmentRepository(db: h.db, userId: integrationActor)
          .hasChangesToUpload('a1'),
      isTrue,
    );
  });

  test(
      'same-second revision history is latest by insertion and claims serialize across workers',
      () async {
    final finalize = FinalizeSubmissionUseCase(h.db);
    await finalize.execute('s1');
    final first = await h.db.select(h.db.syncJobs).getSingle();
    await BuildingAttributesRepository(h.db)
        .upsertForSubmission(submissionId: 's1', buildingName: 'Later');
    await SubmissionRepository(h.db).markStatus('s1', 'ready_to_upload');
    await finalize.execute('s1');
    await h.db
        .update(h.db.syncJobs)
        .write(SyncJobsCompanion(createdAt: Value(DateTime.utc(2026))));
    final jobs = SyncJobsRepository(h.db);
    expect(
      (await jobs.findByEntity('attribution_upload', 's1'))!.id,
      isNot(first.id),
    );
    final claims = await Future.wait(
      [jobs.claimUpToN(3), SyncJobsRepository(h.db).claimUpToN(3)],
    );
    expect(claims.expand((list) => list).map((j) => j.id), [first.id]);
    await jobs.markSuccess(first.id);
    expect(await jobs.claimUpToN(3), hasLength(1));
  });

  test('retry cannot revive obsolete rejected revision after newer acceptance',
      () async {
    final finalize = FinalizeSubmissionUseCase(h.db);
    await finalize.execute('s1');
    final old = await h.db.select(h.db.syncJobs).getSingle();
    await SyncJobsRepository(h.db)
        .markDead(old.id, error: 'rejected', attempts: 1);
    await BuildingAttributesRepository(h.db)
        .upsertForSubmission(submissionId: 's1', buildingName: 'Corrected');
    await SubmissionRepository(h.db).markStatus('s1', 'ready_to_upload');
    await finalize.execute('s1');
    await worker(h.api).drain();
    expect(h.api.submitAttributionCalls, hasLength(1));
    await RetryDeadUseCase(db: h.db, triggerNow: () => worker(h.api).drain())
        .retryAll();
    expect(h.api.submitAttributionCalls, hasLength(1));
    final rows = await h.db.select(h.db.syncJobs).get();
    expect(rows.firstWhere((j) => j.id == old.id).status, 'dead');
  });

  test(
      'photo-only completion of accepted survey queues evidence without another attribution',
      () async {
    await FinalizeSubmissionUseCase(h.db).execute('s1');
    await worker(h.api).drain();
    await h.capturePhoto('s1', 'f1');
    final result = await FinalizeSubmissionUseCase(h.db).execute('s1');
    expect(result.photoCount, 1);
    expect(
      (await h.db.select(h.db.submissions).getSingle()).syncStatus,
      'uploaded',
    );
    await worker(h.api).drain();
    expect(h.api.submitAttributionCalls, hasLength(1));
    expect(
      (await h.db.select(h.db.photos).getSingle()).uploadStatus,
      'uploaded',
    );
  });

  test(
      'receipt for old frozen operation does not mark newer unsent draft uploaded',
      () async {
    final api = HeldReceiptApi();
    await FinalizeSubmissionUseCase(h.db).execute('s1');
    final draining = worker(api).drain();
    await api.received.future;
    await SubmissionRepository(h.db).markStatus('s1', 'in_progress');
    api.release.complete();
    await draining;
    expect(
      (await h.db.select(h.db.submissions).getSingle()).syncStatus,
      'in_progress',
    );
  });
}
