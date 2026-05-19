import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/fake_sync_api.dart';
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
import 'package:firecheck/core/sync/domain/resolution_decision.dart';
import 'package:firecheck/core/sync/domain/submit_attribution_result.dart';
import 'package:firecheck/core/sync/domain/sync_entity_type.dart';
import 'package:firecheck/core/sync/failure/assignment_lock_repository.dart';
import 'package:firecheck/core/sync/worker/sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the P1 fix: when `submit_new_feature_with_dedup_check`
/// returns `dedup_pending`, the worker MUST persist the duplicate pointer
/// locally so the review screen can surface the feature.
void main() {
  late AppDatabase db;
  late FakeSyncApi api;
  late SyncWorker worker;
  final now = DateTime.utc(2026, 5, 19, 10);

  Future<void> seedFeature() async {
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
            isNew: const Value(true),
            createdAt: now,
          ),
        );
  }

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
    await seedFeature();
    await db.into(db.syncJobs).insert(
          SyncJobsCompanion.insert(
            id: 'job-uuid-0000-0001',
            entityType: SyncEntityType.newFeatureUpload,
            entityId: 'f1',
            createdAt: now,
          ),
        );
  });

  tearDown(() => db.close());

  Future<Feature> currentFeature() =>
      (db.select(db.features)..where((t) => t.id.equals('f1'))).getSingle();

  test('committed → pendingDedupOf stays null', () async {
    api.enqueueSubmitNewFeature(
      result: const NewFeatureCommitted('f1'),
    );
    await worker.drain();
    final f = await currentFeature();
    expect(f.pendingDedupOf, isNull);
  });

  test(
      'dedup_pending → pendingDedupOf set so the review list surfaces the feature',
      () async {
    api.enqueueSubmitNewFeature(
      result: const NewFeatureDedupPending(
        pendingId: 'f1',
        possibleDuplicateOf: 'f_remote',
      ),
    );
    await worker.drain();
    final f = await currentFeature();
    expect(f.pendingDedupOf, 'f_remote');

    // Worker still treats the job as completed — parking is local-state,
    // not job-state.
    final job = await (db.select(db.syncJobs)
          ..where((t) => t.id.equals('job-uuid-0000-0001')))
        .getSingle();
    expect(job.status, 'success');
  });

  test('newFeatureResolve → pendingDedupOf cleared on success', () async {
    // Pretend dedup_pending already landed.
    await (db.update(db.features)..where((t) => t.id.equals('f1'))).write(
      const FeaturesCompanion(pendingDedupOf: Value('f_remote')),
    );
    await db.into(db.pendingResolutions).insert(
          PendingResolutionsCompanion.insert(
            targetId: 'f1',
            kind: 'new_feature',
            decision: DedupDecision.keepBoth.wire,
            createdAt: now,
          ),
        );
    await db.into(db.syncJobs).insert(
          SyncJobsCompanion.insert(
            id: 'job-uuid-0000-0002',
            entityType: SyncEntityType.newFeatureResolve,
            entityId: 'f1',
            createdAt: now,
          ),
        );

    await worker.drain();

    final f = await currentFeature();
    expect(f.pendingDedupOf, isNull);
    final pr = await db.select(db.pendingResolutions).get();
    expect(pr, isEmpty);
  });
}
