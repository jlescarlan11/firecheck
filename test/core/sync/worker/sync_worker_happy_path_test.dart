import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/fake_sync_api.dart';
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
import 'package:firecheck/core/sync/domain/finalize_submission.dart';
import 'package:firecheck/core/sync/domain/sync_job_status.dart';
import 'package:firecheck/core/sync/failure/assignment_lock_repository.dart';
import 'package:firecheck/core/sync/worker/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SyncJobsRepository jobs;
  late SubmissionPayloadBuilder payload;
  late AssignmentLockRepository lock;
  late FakeSyncApi api;
  late SyncWorker worker;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    jobs = SyncJobsRepository(db);
    payload = SubmissionPayloadBuilder(db);
    lock = AssignmentLockRepository(db);
    api = FakeSyncApi();
    worker = SyncWorker(api: api, jobs: jobs, payload: payload, lock: lock, db: db);
    final now = DateTime.now();
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'admin',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f1',
            assignmentId: 'a1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.submissions).insert(
          SubmissionsCompanion.insert(
            id: 's1',
            featureId: 'f1',
            createdAt: now,
            updatedAt: now,
            syncStatus: const Value('ready_to_upload'),
          ),
        );
    // Outbox transaction queues a submission sync_job for s1.
    await FinalizeSubmissionUseCase(db).execute('s1');
  });

  tearDown(() async => db.close());

  test('Success → sync_jobs row marked success + submission row uploaded',
      () async {
    await worker.drain();

    final job = await db.select(db.syncJobs).getSingle();
    expect(job.status, SyncJobStatus.success);

    final sub = await (db.select(db.submissions)
          ..where((t) => t.id.equals('s1')))
        .getSingle();
    expect(sub.syncStatus, 'uploaded');

    // FinalizeSubmissionUseCase enqueues `attribution_upload` and the
    // worker routes through the conflict-aware RPC.
    expect(api.submitAttributionCalls, hasLength(1));
  });

  test('drain() de-dupes overlapping calls', () async {
    final f1 = worker.drain();
    final f2 = worker.drain();
    await Future.wait([f1, f2]);
    expect(api.submitAttributionCalls, hasLength(1));
  });
}
