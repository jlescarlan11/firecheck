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
  test('TransientFailure → attempts++ + next_retry_at scheduled', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    final api = FakeSyncApi()..enqueueSubmitAttribution(outcome: const TransientFailure('500'));
    final worker = SyncWorker(
      api: api,
      jobs: SyncJobsRepository(db),
      payload: SubmissionPayloadBuilder(db),
      lock: AssignmentLockRepository(db),
      db: db,
    );
    await worker.drain();
    final job = await db.select(db.syncJobs).getSingle();
    expect(job.status, SyncJobStatus.pending);
    expect(job.attempts, 1);
    expect(job.lastError, '500');
    expect(job.nextRetryAt, isNotNull);
  });

  test('5th TransientFailure → marked dead', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    final jobBefore = await db.select(db.syncJobs).getSingle();
    await (db.update(db.syncJobs)
          ..where((t) => t.id.equals(jobBefore.id)))
        .write(const SyncJobsCompanion(attempts: Value(4)));
    final api = FakeSyncApi()..enqueueSubmitAttribution(outcome: const TransientFailure('500'));
    final worker = SyncWorker(
      api: api,
      jobs: SyncJobsRepository(db),
      payload: SubmissionPayloadBuilder(db),
      lock: AssignmentLockRepository(db),
      db: db,
    );
    await worker.drain();
    final job = await db.select(db.syncJobs).getSingle();
    expect(job.status, SyncJobStatus.dead);
    expect(job.attempts, 5);
  });

  test('PermanentFailure (4xx other) → marked dead immediately', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);
    final api = FakeSyncApi()
      ..enqueueSubmitAttribution(outcome: const PermanentFailure('400 bad request'));
    final worker = SyncWorker(
      api: api,
      jobs: SyncJobsRepository(db),
      payload: SubmissionPayloadBuilder(db),
      lock: AssignmentLockRepository(db),
      db: db,
    );
    await worker.drain();
    final job = await db.select(db.syncJobs).getSingle();
    expect(job.status, SyncJobStatus.dead);
    expect(job.attempts, 1);
    expect(job.lastError, '400 bad request');
  });
}
