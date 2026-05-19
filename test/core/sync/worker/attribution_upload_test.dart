import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/fake_sync_api.dart';
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
import 'package:firecheck/core/sync/domain/submit_attribution_result.dart';
import 'package:firecheck/core/sync/domain/sync_entity_type.dart';
import 'package:firecheck/core/sync/failure/assignment_lock_repository.dart';
import 'package:firecheck/core/sync/worker/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late FakeSyncApi api;
  late SyncWorker worker;
  final now = DateTime.utc(2026, 5, 19, 10);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    api = FakeSyncApi();
    worker = SyncWorker(
      api: api,
      jobs: SyncJobsRepository(db),
      payload: SubmissionPayloadBuilder(db),
      lock: AssignmentLockRepository(db),
      db: db,
    );

    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'me',
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
            syncStatus: const Value('queued'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db.into(db.syncJobs).insert(
          SyncJobsCompanion.insert(
            id: 'job-uuid-0000-0001',
            entityType: SyncEntityType.attributionUpload,
            entityId: 's1',
            createdAt: now,
          ),
        );
  });

  tearDown(() => db.close());

  Future<Submission> currentSubmission() =>
      (db.select(db.submissions)..where((t) => t.id.equals('s1'))).getSingle();

  test('committed → submission marked uploaded', () async {
    api.enqueueSubmitAttribution(
      result: const AttributionCommitted('s1'),
    );
    await worker.drain();
    final s = await currentSubmission();
    expect(s.syncStatus, 'uploaded');
    expect(s.pendingTheirsId, isNull);
  });

  test('agreed_skip → submission marked withdrawn', () async {
    api.enqueueSubmitAttribution(
      result: const AttributionAgreedSkip('s_remote'),
    );
    await worker.drain();
    final s = await currentSubmission();
    expect(s.syncStatus, 'withdrawn');
    expect(s.pendingTheirsId, isNull);
  });

  test('conflict → submission parked with pendingTheirsId set', () async {
    api.enqueueSubmitAttribution(
      result: const AttributionConflict(
        pendingId: 's1',
        theirSubmissionId: 's_remote',
      ),
    );
    await worker.drain();
    final s = await currentSubmission();
    expect(s.syncStatus, 'awaiting_user_resolution');
    expect(s.pendingTheirsId, 's_remote');

    // The job itself succeeded — parking is a state on the submission,
    // not on the job (worker terminology: outcome=Success).
    final job = await (db.select(db.syncJobs)
          ..where((t) => t.id.equals('job-uuid-0000-0001')))
        .getSingle();
    expect(job.status, 'success');
  });
}
