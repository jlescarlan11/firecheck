import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/fake_sync_api.dart';
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
import 'package:firecheck/core/sync/domain/sync_job_status.dart';
import 'package:firecheck/core/sync/domain/sync_outcome.dart';
import 'package:firecheck/core/sync/failure/assignment_lock_repository.dart';
import 'package:firecheck/core/sync/worker/sync_worker.dart';
import 'package:firecheck/features/map/geometry_editor/data/feature_geometry_revisions_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SyncJobsRepository jobs;
  late SubmissionPayloadBuilder payload;
  late AssignmentLockRepository lock;
  late FakeSyncApi api;
  late SyncWorker worker;
  late FeatureGeometryRevisionsRepository revRepo;

  const revisionId = 'rev-1';
  const featureId = 'f1';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    jobs = SyncJobsRepository(db);
    payload = SubmissionPayloadBuilder(db);
    lock = AssignmentLockRepository(db);
    api = FakeSyncApi();
    worker = SyncWorker(api: api, jobs: jobs, payload: payload, lock: lock, db: db);
    revRepo = FeatureGeometryRevisionsRepository(db);

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
            id: featureId,
            assignmentId: 'a1',
            featureType: 'building',
            geometryGeojson: '{"old":true}',
            createdAt: now,
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> seedRevision() async {
    await revRepo.saveReshape(
      revisionId: revisionId,
      featureId: featureId,
      prevGeojson: '{"old":true}',
      newGeojson: '{"new":true}',
      editedBy: 'admin',
      editedAt: DateTime.now(),
      overrideReason: null,
    );
  }

  test(
    'success: revision.syncStatus == uploaded, sync_job.status == success',
    () async {
      await seedRevision();

      // No enqueue needed — FakeSyncApi defaults to Success.
      await worker.drain();

      final rev = await revRepo.getById(revisionId);
      expect(rev, isNotNull);
      expect(rev!.syncStatus, 'uploaded');

      final job = await jobs.findByEntity('feature_geometry_update', revisionId);
      expect(job, isNotNull);
      expect(job!.status, SyncJobStatus.success);

      expect(api.uploadFeatureGeometryUpdateCalls, hasLength(1));
      expect(api.uploadFeatureGeometryUpdateCalls.first.id, revisionId);
    },
  );

  test(
    'permanent failure: revision.syncStatus == failed, sync_job.status == dead',
    () async {
      await seedRevision();

      api.enqueueFeatureGeometryUpdate(
          const PermanentFailure('geometry_conflict'),);

      await worker.drain();

      final rev = await revRepo.getById(revisionId);
      expect(rev, isNotNull);
      expect(rev!.syncStatus, 'failed');

      final job = await jobs.findByEntity('feature_geometry_update', revisionId);
      expect(job, isNotNull);
      expect(job!.status, SyncJobStatus.dead);

      expect(api.uploadFeatureGeometryUpdateCalls, hasLength(1));
      expect(api.uploadFeatureGeometryUpdateCalls.first.id, revisionId);
    },
  );
}
