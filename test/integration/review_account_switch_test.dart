import 'dart:async';

import 'package:firecheck/core/drive/drive_upload_audit_repository.dart';
import 'package:firecheck/core/drive/drive_upload_providers.dart'
    hide driveUploadNotifierProvider;
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:firecheck/core/drive/enqueue_assignment_use_case.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_exporter.dart';
import 'package:firecheck/features/review/domain/upload_confirmer.dart';
import 'package:firecheck/features/review/domain/upload_flow_outcome.dart';
import 'package:firecheck/features/review/presentation/review_providers.dart';
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
  testWidgets(
      'account switch before legacy export cannot rebind A completed survey to B jobs',
      (tester) async {
    final h = (await tester
        .runAsync(() => SurveyIntegrationFixture.ready(shared: false)))!;
    var actor = integrationActor;
    await h.mount(
      tester,
      route: '/review',
      overrides: [
        enqueueAssignmentUseCaseProvider.overrideWith(
          (ref) => EnqueueAssignmentUseCase(
            db: h.db,
            repo: ref.watch(driveUploadRepoProvider),
            exporter: ShapefileExporter(db: h.db, tempDirOverride: h.directory),
            currentUserId: () => actor,
          ),
        ),
        driveUploadWorkerProvider.overrideWith(
          (ref) => DriveUploadWorker(
            api: h.drive,
            repo: ref.watch(driveUploadRepoProvider),
            db: h.db,
            enumeratorIdentifier: () => actor,
            currentUserId: () => actor,
          ),
        ),
      ],
    );
    addTearDown(() => h.close(tester));
    final entered = Completer<void>();
    final release = Completer<void>();
    h.api.beforeAttribution = () async {
      entered.complete();
      await release.future;
    };
    final useCase = h.container.read(executeAssignmentUploadUseCaseProvider);
    final snapshot = h.container.read(reviewStateProvider).requireValue;
    late Future<UploadFlowOutcome> running;
    await tester.runAsync(() async {
      running = useCase.execute(
        state: snapshot,
        currentUserId: integrationActor,
        confirmer: _Confirm(),
      );
    });
    await h.until(tester, () => entered.isCompleted);
    actor = 'B';
    release.complete();
    expect(
      await h.resolve(tester, () => running),
      isNot(isA<UploadFlowSucceeded>()),
    );
    expect(h.drive.files, isEmpty);
    expect(
      await h.resolve(tester, () => h.db.select(h.db.driveUploadJobs).get()),
      isEmpty,
    );
    expect(h.audit.accepted, isEmpty);
    await h.close(tester);
  });
}
