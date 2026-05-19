import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/fake_sync_api.dart';
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
import 'package:firecheck/core/sync/domain/finalize_submission.dart';
import 'package:firecheck/core/sync/domain/sync_job_status.dart';
import 'package:firecheck/core/sync/domain/sync_outcome.dart';
import 'package:firecheck/core/sync/failure/assignment_lock_repository.dart';
import 'package:firecheck/core/sync/worker/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _seed(AppDatabase db) async {
  final now = DateTime.now();
  await db.into(db.assignments).insert(AssignmentsCompanion.insert(
        id: 'a1',
        enumeratorId: 'admin',
        campaignId: 'c1',
        boundaryPolygonGeojson: '{}',
        createdAt: now,
      ),);
  await db.into(db.features).insert(FeaturesCompanion.insert(
        id: 'f1',
        assignmentId: 'a1',
        featureType: 'building',
        geometryGeojson: '{}',
        createdAt: now,
      ),);
  await db.into(db.submissions).insert(SubmissionsCompanion.insert(
        id: 's1',
        featureId: 'f1',
        createdAt: now,
        updatedAt: now,
        syncStatus: const Value('ready_to_upload'),
      ),);
  await FinalizeSubmissionUseCase(db).execute('s1');
}

void main() {
  test('AuthExpired → refresh succeeds → retry inline → Success', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    final api = FakeSyncApi()
      ..enqueueSubmitAttribution(outcome: const AuthExpired())
      ..enqueueSubmitAttribution();
    var refreshCalls = 0;
    final worker = SyncWorker(
      api: api,
      jobs: SyncJobsRepository(db),
      payload: SubmissionPayloadBuilder(db),
      lock: AssignmentLockRepository(db),
      db: db,
      refreshSession: () async {
        refreshCalls++;
        return true;
      },
    );
    await worker.drain();
    expect(refreshCalls, 1);
    final job = await db.select(db.syncJobs).getSingle();
    expect(job.status, SyncJobStatus.success);
  });

  test('AuthExpired → refresh fails → marked pending+attempts++', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    final api = FakeSyncApi()
      ..enqueueSubmitAttribution(outcome: const AuthExpired());
    final worker = SyncWorker(
      api: api,
      jobs: SyncJobsRepository(db),
      payload: SubmissionPayloadBuilder(db),
      lock: AssignmentLockRepository(db),
      db: db,
      refreshSession: () async => false,
    );
    await worker.drain();
    final job = await db.select(db.syncJobs).getSingle();
    expect(job.status, SyncJobStatus.pending);
    expect(job.attempts, 1);
    expect(job.lastError, contains('auth refresh'));
  });

  test('AuthExpired → refresh ok but retry returns AuthExpired again → transient',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    final api = FakeSyncApi()
      ..enqueueSubmitAttribution(outcome: const AuthExpired())
      ..enqueueSubmitAttribution(outcome: const AuthExpired());
    final worker = SyncWorker(
      api: api,
      jobs: SyncJobsRepository(db),
      payload: SubmissionPayloadBuilder(db),
      lock: AssignmentLockRepository(db),
      db: db,
      refreshSession: () async => true,
    );
    await worker.drain();
    final job = await db.select(db.syncJobs).getSingle();
    expect(job.status, SyncJobStatus.pending);
    expect(job.attempts, 1);
    expect(job.lastError, contains('repeat 401'));
  });
}
