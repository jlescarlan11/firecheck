import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_audit_repository.dart';
import 'package:firecheck/core/sync/domain/submit_attribution_result.dart';
import 'package:firecheck/core/sync/domain/sync_outcome.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/review/domain/upload_confirmer.dart';
import 'package:firecheck/features/review/domain/upload_flow_outcome.dart';
import 'package:firecheck/features/review/presentation/review_providers.dart';
import 'package:firecheck/features/survey/building_form/data/building_attributes_repository.dart';
import 'package:firecheck/features/survey/building_form/data/submission_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/survey_integration_fixture.dart';

class _Confirm extends UploadConfirmer {
  @override
  Future<bool> confirmPartial({
    required int unsurveyedCount,
    required int totalFeatures,
  }) async =>
      true;
  @override
  Future<bool> confirmOverwrite({
    required List<DriveUploadAudit> priorUploads,
    required String? currentUserId,
  }) async =>
      true;
  @override
  Future<bool> confirmUnverified() async => true;
}

void main() {
  for (final shared in [false, true]) {
    for (final failure in ['offline', 'rejected']) {
      testWidgets(
          'real ${shared ? 'shared' : 'legacy'} review orchestration preserves $failure work and retries same operation',
          (tester) async {
        final h = (await tester
            .runAsync(() => SurveyIntegrationFixture.ready(shared: shared)))!;
        await h.mount(tester, route: '/review');
        addTearDown(() => h.close(tester));
        h.api.enqueueSubmitAttribution(
          outcome: failure == 'offline'
              ? const TransientFailure('offline')
              : const PermanentFailure('rejected'),
        );
        final useCase =
            h.container.read(executeAssignmentUploadUseCaseProvider);
        final snapshot = h.container.read(reviewStateProvider).requireValue;
        Future<UploadFlowOutcome> execute() => useCase.execute(
              state: snapshot,
              currentUserId: integrationActor,
              confirmer: _Confirm(),
            );
        final result = await h.resolve(tester, execute);
        expect(result, isNot(isA<UploadFlowSucceeded>()));
        final queued = await h.resolve(
          tester,
          () => h.db.select(h.db.submissions).getSingle(),
        );
        expect(queued.syncStatus, 'queued');
        expect(h.drive.files, isEmpty);
        expect(h.audit.accepted, isEmpty);
        final firstId =
            h.api.submitAttributionCalls.single.payload['operation_id'];
        await h.resolve(tester, () async {
          await h.db.update(h.db.syncJobs).write(
                const SyncJobsCompanion(
                  status: Value('pending'),
                  nextRetryAt: Value(null),
                ),
              );
        });
        final retry = await h.resolve(tester, execute);
        expect(
          retry,
          shared ? isA<UploadFlowSynced>() : isA<UploadFlowSucceeded>(),
        );
        expect(h.api.submitAttributionCalls, hasLength(2));
        expect(
          h.api.submitAttributionCalls.last.payload['operation_id'],
          firstId,
        );
        expect(
          (await h.resolve(
            tester,
            () => h.db.select(h.db.submissions).getSingle(),
          ))
              .syncStatus,
          'uploaded',
        );
        await h.close(tester);
      });
    }
  }

  for (final shared in [false, true]) {
    testWidgets(
        'in-flight ${shared ? 'shared' : 'legacy'} review keeps captured map and actor after selection changes',
        (tester) async {
      final h = (await tester
          .runAsync(() => SurveyIntegrationFixture.ready(shared: shared)))!;
      await h.mount(tester, route: '/review');
      addTearDown(() => h.close(tester));
      final received = Completer<void>();
      final release = Completer<void>();
      h.api.beforeAttribution = () async {
        received.complete();
        await release.future;
      };
      final useCase = h.container.read(executeAssignmentUploadUseCaseProvider);
      late Future<UploadFlowOutcome> running;
      await tester.runAsync(() async {
        running = useCase.execute(
          state: h.container.read(reviewStateProvider).requireValue,
          currentUserId: integrationActor,
          confirmer: _Confirm(),
        );
      });
      await h.until(tester, () => received.isCompleted);
      await h.resolve(tester, () async {
        await h.db.into(h.db.assignments).insert(
              AssignmentsCompanion.insert(
                id: 'a2',
                enumeratorId: integrationActor,
                campaignId: 'c2',
                boundaryPolygonGeojson: integrationBoundary,
                createdAt: DateTime.utc(2026),
              ),
            );
        await h.container
            .read(assignmentRepositoryProvider)
            .selectAssignment('a2');
      });
      await h.until(
        tester,
        () =>
            h.container.read(currentAssignmentProvider).valueOrNull?.id == 'a2',
      );
      release.complete();
      final result = await h.resolve(tester, () => running);
      expect(
        result,
        shared ? isA<UploadFlowSynced>() : isA<UploadFlowSucceeded>(),
      );
      expect(
        (h.api.submitAttributionCalls.single.payload['submission']
            as Map)['submitted_by'],
        integrationActor,
      );
      expect(
        (h.api.submitAttributionCalls.single.payload['submission']
            as Map)['feature_id'],
        'f1',
      );
      final jobs = await h.resolve(
        tester,
        () => h.db.select(h.db.driveUploadJobs).get(),
      );
      expect(
        jobs.every(
          (j) => j.assignmentId == 'a1' && j.ownerId == integrationActor,
        ),
        isTrue,
      );
      final assignments =
          await h.resolve(tester, () => h.db.select(h.db.assignments).get());
      expect(
        assignments.firstWhere((a) => a.id == 'a2').driveUploadConfirmedAt,
        isNull,
      );
      await h.close(tester);
    });
  }

  for (final shared in [false, true]) {
    testWidgets(
        '${shared ? 'shared' : 'legacy'} review uploads completed subset while an unrelated photographed draft stays private',
        (tester) async {
      final h = (await tester
          .runAsync(() => SurveyIntegrationFixture.ready(shared: shared)))!;
      await tester.runAsync(() async {
        await h.db.into(h.db.features).insert(
              FeaturesCompanion.insert(
                id: 'f2',
                assignmentId: 'a1',
                featureType: 'building',
                geometryGeojson: (await h.db.select(h.db.features).getSingle())
                    .geometryGeojson,
                createdAt: DateTime.utc(2026),
              ),
            );
        await h.db.into(h.db.submissions).insert(
              SubmissionsCompanion.insert(
                id: 'draft2',
                featureId: 'f2',
                submittedBy: const Value(integrationActor),
                syncStatus: const Value('draft'),
                createdAt: DateTime.utc(2026),
                updatedAt: DateTime.utc(2026),
              ),
            );
        await h.capturePhoto('draft2', 'f2');
      });
      await h.mount(tester, route: '/review');
      addTearDown(() => h.close(tester));
      final result = await h.resolve(
        tester,
        () => h.container.read(executeAssignmentUploadUseCaseProvider).execute(
              state: h.container.read(reviewStateProvider).requireValue,
              currentUserId: integrationActor,
              confirmer: _Confirm(),
            ),
      );
      expect(
        result,
        shared ? isA<UploadFlowSynced>() : isA<UploadFlowSucceeded>(),
      );
      if (result is UploadFlowSynced) {
        expect(result.pending, 0);
        expect(result.pendingPhotos, 0);
      }
      expect(h.api.submitAttributionCalls, hasLength(1));
      expect(
        (h.api.submitAttributionCalls.single.payload['submission']
            as Map)['id'],
        's1',
      );
      final drafts = await h.resolve(
        tester,
        () => (h.db.select(h.db.submissions)
              ..where((t) => t.id.equals('draft2')))
            .getSingle(),
      );
      expect(drafts.syncStatus, 'draft');
      await h.close(tester);
    });
  }

  testWidgets('legacy transport failure preserves one export batch for retry',
      (tester) async {
    final h = (await tester
        .runAsync(() => SurveyIntegrationFixture.ready(shared: false)))!;
    await h.mount(tester, route: '/review');
    addTearDown(() => h.close(tester));
    h.drive.offline = true;
    final useCase = h.container.read(executeAssignmentUploadUseCaseProvider);
    final snapshot = h.container.read(reviewStateProvider).requireValue;
    Future<UploadFlowOutcome> execute() => useCase.execute(
          state: snapshot,
          currentUserId: integrationActor,
          confirmer: _Confirm(),
        );
    expect(await h.resolve(tester, execute), isA<UploadFlowIncomplete>());
    expect(h.audit.accepted, isEmpty);
    expect(h.drive.files, isEmpty);
    final originalJobs =
        await h.resolve(tester, () => h.db.select(h.db.driveUploadJobs).get());
    expect(originalJobs, hasLength(4));
    await h.resolve(tester, () async {
      final dbf = originalJobs.firstWhere((j) => j.fileName.endsWith('.dbf'));
      final bytes = await File(dbf.filePath).readAsBytes();
      bytes[1] = 125;
      bytes[2] = 1;
      bytes[3] = 1;
      await File(dbf.filePath).writeAsBytes(bytes);
    });
    h.drive.offline = false;
    await h.resolve(tester, () async {
      await h.db
          .update(h.db.driveUploadJobs)
          .write(const DriveUploadJobsCompanion(nextRetryAt: Value(null)));
    });
    expect(await h.resolve(tester, execute), isA<UploadFlowSucceeded>());
    expect(h.drive.files, hasLength(4));
    expect(
      (await h.resolve(tester, () => h.db.select(h.db.driveUploadJobs).get()))
          .map((j) => j.id)
          .toSet(),
      originalJobs.map((j) => j.id).toSet(),
    );
    await h.close(tester);
  });

  testWidgets(
      'intentional legacy revision after interrupted export preserves old files and uploads a new FIFO batch',
      (tester) async {
    final h = (await tester
        .runAsync(() => SurveyIntegrationFixture.ready(shared: false)))!;
    await h.mount(tester, route: '/review');
    addTearDown(() => h.close(tester));
    h.drive.offline = true;
    final useCase = h.container.read(executeAssignmentUploadUseCaseProvider);
    final snapshot = h.container.read(reviewStateProvider).requireValue;
    Future<UploadFlowOutcome> execute() => useCase.execute(
        state: snapshot,
        currentUserId: integrationActor,
        confirmer: _Confirm(),);
    expect(await h.resolve(tester, execute), isA<UploadFlowIncomplete>());
    final old =
        await h.resolve(tester, () => h.db.select(h.db.driveUploadJobs).get());
    final frozen = await h.resolve(
        tester,
        () async => {
              for (final job in old)
                job.filePath: await File(job.filePath).readAsBytes(),
            },);
    await h.resolve(tester, () async {
      await BuildingAttributesRepository(h.db).upsertForSubmission(
          submissionId: 's1',
          buildingName: 'New intentional export',
          ra9514Type: 'C',);
      await SubmissionRepository(h.db).markStatus('s1', 'ready_to_upload');
      await h.db
          .update(h.db.driveUploadJobs)
          .write(const DriveUploadJobsCompanion(nextRetryAt: Value(null)));
    });
    h.drive.offline = false;
    expect(await h.resolve(tester, execute), isA<UploadFlowSucceeded>());
    expect(h.api.submitAttributionCalls, hasLength(2));
    expect(h.drive.files, hasLength(8));
    expect(h.drive.acceptedPaths.take(4).toSet(),
        old.map((job) => job.filePath).toSet(),);
    expect(
        h.drive.acceptedPaths
            .skip(4)
            .toSet()
            .intersection(old.map((job) => job.filePath).toSet()),
        isEmpty,);
    final current =
        await h.resolve(tester, () => h.db.select(h.db.driveUploadJobs).get());
    expect(current, hasLength(8));
    expect(current.map((j) => j.filePath).toSet(), hasLength(8));
    for (final original in old) {
      expect(
          await h.resolve(tester, () => File(original.filePath).readAsBytes()),
          frozen[original.filePath],);
    }
    await h.close(tester);
  });

  for (final pending in ['photo', 'geometry', 'conflict']) {
    testWidgets(
        'real shared review reports pending $pending rather than complete sync',
        (tester) async {
      final h = (await tester
          .runAsync(() => SurveyIntegrationFixture.ready(shared: true)))!;
      await h.mount(tester, route: '/review');
      addTearDown(() => h.close(tester));
      if (pending == 'photo') {
        h.api.enqueuePhotoUpload(const TransientFailure('offline media'));
      }
      if (pending == 'conflict') {
        h.api.enqueueSubmitAttribution(
          result: const AttributionConflict(
            pendingId: 'pending',
            theirSubmissionId: 'theirs',
          ),
        );
      }
      if (pending == 'geometry') {
        await h.resolve(tester, () async {
          final geometry =
              (await h.db.select(h.db.features).getSingle()).geometryGeojson;
          await h.db.into(h.db.featureGeometryRevisions).insert(
                FeatureGeometryRevisionsCompanion.insert(
                  id: 'g1',
                  featureId: 'f1',
                  prevGeojson: geometry,
                  newGeojson: geometry,
                  editedBy: integrationActor,
                  editedAt: DateTime.utc(2026),
                  createdAt: DateTime.utc(2026),
                ),
              );
        });
      }
      final result = await h.resolve(
        tester,
        () => h.container.read(executeAssignmentUploadUseCaseProvider).execute(
              state: h.container.read(reviewStateProvider).requireValue,
              currentUserId: integrationActor,
              confirmer: _Confirm(),
            ),
      );
      expect(result, isA<UploadFlowSynced>());
      final synced = result as UploadFlowSynced;
      if (pending == 'photo') expect(synced.pendingPhotos, 1);
      if (pending == 'geometry') expect(synced.pendingGeometry, 1);
      if (pending == 'conflict') expect(synced.conflicts, 1);
      expect(h.drive.files, isEmpty);
      await h.close(tester);
    });
  }
}
