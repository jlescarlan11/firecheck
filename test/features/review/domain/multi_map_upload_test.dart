import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_audit_repository.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:firecheck/core/drive/enqueue_assignment_use_case.dart';
import 'package:firecheck/core/drive/finalize_assignment_upload_use_case.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:firecheck/features/review/domain/execute_assignment_upload_use_case.dart';
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/domain/upload_confirmer.dart';
import 'package:firecheck/features/review/domain/upload_flow_outcome.dart';
import 'package:firecheck/features/review/domain/upload_progress.dart';
import 'package:firecheck/features/review/presentation/sub/start_upload_use_case.dart';
import 'package:firecheck/features/review/presentation/upload_progress_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Audit extends Mock implements DriveUploadAuditRepository {}

class _Start extends Mock implements StartUploadUseCase {}

class _Enqueue extends Mock implements EnqueueAssignmentUseCase {}

class _Job extends Mock implements DriveUploadJob {}

class _Jobs extends Mock implements DriveUploadRepository {}

class _Worker extends Mock implements DriveUploadWorker {}

class _Finalize extends Mock implements FinalizeAssignmentUploadUseCase {}

class _Confirm extends Mock implements UploadConfirmer {}

void main() {
  test('shared sync reports pending geometry instead of complete success',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = AssignmentRepository(db: db, userId: 'me');
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'map',
            enumeratorId: 'me',
            campaignId: 'map',
            boundaryPolygonGeojson: '{}',
            createdAt: DateTime(2026),
          ),
        );
    await db.into(db.sharedMapCursors).insert(
          SharedMapCursorsCompanion.insert(
            accountId: 'me',
            assignmentId: 'map',
          ),
        );
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'feature',
            assignmentId: 'map',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: DateTime(2026),
          ),
        );
    await db.into(db.featureGeometryRevisions).insert(
          FeatureGeometryRevisionsCompanion.insert(
            id: 'geometry',
            featureId: 'feature',
            prevGeojson: '{}',
            newGeojson: '{}',
            editedBy: 'me',
            editedAt: DateTime(2026),
            createdAt: DateTime(2026),
            syncStatus: const Value('ready_to_upload'),
          ),
        );
    final start = _Start();
    when(() => start.execute('map'))
        .thenAnswer((_) async => const StartUploadResult(finalizedCount: 0));
    final progress = UploadProgressController(jobsStream: const Stream.empty());
    addTearDown(progress.dispose);
    final useCase = ExecuteAssignmentUploadUseCase(
      sharedDb: db,
      assignmentRepository: repo,
      auditRepository: _Audit(),
      startUploadUseCase: start,
      enqueueAssignmentUseCase: _Enqueue(),
      driveUploadRepository: _Jobs(),
      driveUploadWorker: _Worker(),
      finalizeAssignmentUploadUseCase: _Finalize(),
      progressController: progress,
    );
    const state = ReviewState(
      assignmentId: 'map',
      summary: ReviewSummary(
        totalFeatures: 0,
        completeFeatures: 0,
        incompleteFeatures: 0,
        newFeaturesAdded: 0,
        photosPending: 0,
      ),
      warnings: [],
      blockers: [],
      deadJobs: [],
      upload: Idle(),
    );
    final result = await useCase.execute(
      state: state,
      currentUserId: 'me',
      confirmer: _Confirm(),
    );
    expect((result as UploadFlowSynced).pendingGeometry, 1);
    await (db.update(db.featureGeometryRevisions)
          ..where((r) => r.id.equals('geometry')))
        .write(
      const FeatureGeometryRevisionsCompanion(
        syncStatus: Value('discarded'),
      ),
    );
    final resolved = await useCase.execute(
      state: state,
      currentUserId: 'me',
      confirmer: _Confirm(),
    );
    expect((resolved as UploadFlowSynced).pendingGeometry, 0);
  });

  for (final fails in [false, true]) {
    test('Drive completion clears zero-job progress (throws: $fails)',
        () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = AssignmentRepository(db: db, userId: 'me');
      await db.into(db.assignments).insert(
            AssignmentsCompanion.insert(
              id: 'cebu',
              enumeratorId: 'me',
              campaignId: 'cebu',
              boundaryPolygonGeojson: '',
              createdAt: DateTime(2026, 5),
            ),
          );
      final audit = _Audit();
      when(() => audit.listForAssignment('cebu'))
          .thenAnswer((_) async => const AuditProbeAvailable([]));
      final start = _Start();
      when(() => start.execute('cebu'))
          .thenAnswer((_) async => const StartUploadResult(finalizedCount: 0));
      final enqueue = _Enqueue();
      when(() => enqueue.execute(assignmentId: 'cebu', expectedOwnerId: 'me'))
          .thenAnswer((_) async => 0);
      final jobs = _Jobs();
      when(() => jobs.getJobsForAssignment('cebu'))
          .thenAnswer((_) async => [_Job()]);
      final worker = _Worker();
      final progress =
          UploadProgressController(jobsStream: const Stream.empty());
      addTearDown(progress.dispose);
      when(worker.drain).thenAnswer((_) async {
        expect((progress.state as InProgress).label, 'Uploading files…');
        if (fails) throw StateError('Drive failed');
      });
      final finalize = _Finalize();
      when(() => finalize.execute(assignmentId: 'cebu', uploaderId: 'me'))
          .thenAnswer(
        (_) async => DriveUploadSucceeded(
          assignmentId: 'cebu',
          folderPath: 'output/cebu',
          completedCount: 1,
          confirmedAt: DateTime(2026, 5, 2),
        ),
      );
      final result = ExecuteAssignmentUploadUseCase(
        assignmentRepository: repo,
        auditRepository: audit,
        startUploadUseCase: start,
        enqueueAssignmentUseCase: enqueue,
        driveUploadRepository: jobs,
        driveUploadWorker: worker,
        finalizeAssignmentUploadUseCase: finalize,
        progressController: progress,
      ).execute(
        state: const ReviewState(
          assignmentId: 'cebu',
          summary: ReviewSummary(
            totalFeatures: 1,
            completeFeatures: 1,
            incompleteFeatures: 0,
            newFeaturesAdded: 0,
            photosPending: 0,
          ),
          warnings: [],
          blockers: [],
          deadJobs: [],
          upload: Idle(),
        ),
        currentUserId: 'me',
        confirmer: _Confirm(),
      );
      if (fails) {
        await expectLater(result, throwsStateError);
      } else {
        expect(await result, isA<UploadFlowSucceeded>());
      }
      expect(progress.state, isA<Idle>());
    });
  }

  test('confirmed unchanged upload bypasses confirmations and network phases',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = AssignmentRepository(db: db, userId: 'me');
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'cebu',
            enumeratorId: 'me',
            campaignId: 'cebu',
            boundaryPolygonGeojson: '',
            createdAt: DateTime(2026, 5),
          ),
        );
    await repo.setDriveUploadResult(
      assignmentId: 'cebu',
      driveFolderPath: 'output/cebu',
      driveFolderUrl: '',
      driveUploadConfirmedAt: DateTime(2026, 5, 2),
    );
    final audit = _Audit();
    final start = _Start();
    final enqueue = _Enqueue();
    final worker = _Worker();
    final confirm = _Confirm();
    final progress = UploadProgressController(jobsStream: const Stream.empty());
    addTearDown(progress.dispose);
    final result = await ExecuteAssignmentUploadUseCase(
      assignmentRepository: repo,
      auditRepository: audit,
      startUploadUseCase: start,
      enqueueAssignmentUseCase: enqueue,
      driveUploadRepository: _Jobs(),
      driveUploadWorker: worker,
      finalizeAssignmentUploadUseCase: _Finalize(),
      progressController: progress,
    ).execute(
      state: const ReviewState(
        assignmentId: 'cebu',
        summary: ReviewSummary(
          totalFeatures: 1,
          completeFeatures: 1,
          incompleteFeatures: 0,
          newFeaturesAdded: 0,
          photosPending: 0,
        ),
        warnings: [],
        blockers: [],
        deadJobs: [],
        upload: Idle(),
      ),
      currentUserId: 'me',
      confirmer: confirm,
    );
    expect(result, isA<UploadFlowSucceeded>());
    expect((result as UploadFlowSucceeded).confirmedAt, DateTime(2026, 5, 2));
    verifyZeroInteractions(audit);
    verifyZeroInteractions(start);
    verifyZeroInteractions(enqueue);
    verifyZeroInteractions(worker);
    verifyZeroInteractions(confirm);
  });

  test(
      'changing selection during confirmation cannot retarget the reviewed upload',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = AssignmentRepository(db: db, userId: 'me');
    for (final id in ['cebu', 'guadalupe']) {
      await db.into(db.assignments).insert(
            AssignmentsCompanion.insert(
              id: id,
              enumeratorId: 'me',
              campaignId: id,
              boundaryPolygonGeojson: '',
              createdAt: DateTime.now(),
            ),
          );
    }
    await repo.selectAssignment('cebu');
    final audit = _Audit();
    final start = _Start();
    final confirm = _Confirm();
    when(() => audit.listForAssignment('cebu'))
        .thenAnswer((_) async => const AuditProbeUnavailable('offline'));
    when(confirm.confirmUnverified).thenAnswer((_) async {
      await repo.selectAssignment('guadalupe');
      return true;
    });
    // Stop before external work; the assertion checks the captured phase target.
    when(() => start.execute('cebu')).thenThrow(StateError('test stop'));
    final progress = UploadProgressController(jobsStream: const Stream.empty());
    addTearDown(progress.dispose);
    final useCase = ExecuteAssignmentUploadUseCase(
      assignmentRepository: repo,
      auditRepository: audit,
      startUploadUseCase: start,
      enqueueAssignmentUseCase: _Enqueue(),
      driveUploadRepository: _Jobs(),
      driveUploadWorker: _Worker(),
      finalizeAssignmentUploadUseCase: _Finalize(),
      progressController: progress,
    );
    final result = await useCase.execute(
      state: const ReviewState(
        assignmentId: 'cebu',
        summary: ReviewSummary(
          totalFeatures: 1,
          completeFeatures: 1,
          incompleteFeatures: 0,
          newFeaturesAdded: 0,
          photosPending: 0,
        ),
        warnings: [],
        blockers: [],
        deadJobs: [],
        upload: Idle(),
      ),
      currentUserId: 'me',
      confirmer: confirm,
    );
    expect(result, isA<UploadFlowSupabaseFailed>());
    expect((await repo.getCurrentAssignment())?.id, 'guadalupe');
    verify(() => start.execute('cebu')).called(1);
    verifyNever(() => start.execute('guadalupe'));
  });
}
