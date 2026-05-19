import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/fake_sync_api.dart';
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
import 'package:firecheck/core/sync/domain/resolution_decision.dart';
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
            syncStatus: const Value('awaiting_user_resolution'),
            pendingTheirsId: const Value('s_remote'),
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() => db.close());

  Future<Submission> currentSubmission() =>
      (db.select(db.submissions)..where((t) => t.id.equals('s1'))).getSingle();

  Future<void> seedResolve(String wire) async {
    await db.into(db.pendingResolutions).insert(
          PendingResolutionsCompanion.insert(
            targetId: 's1',
            kind: 'attribution',
            decision: wire,
            createdAt: now,
          ),
        );
    await db.into(db.syncJobs).insert(
          SyncJobsCompanion.insert(
            id: 'j_resolve',
            entityType: SyncEntityType.attributionResolve,
            entityId: 's1',
            createdAt: now,
          ),
        );
  }

  test('keep_theirs → submission flipped to withdrawn, resolution cleared',
      () async {
    await seedResolve(AttributionDecision.keepTheirs.wire);
    await worker.drain();

    final s = await currentSubmission();
    expect(s.syncStatus, 'withdrawn');
    expect(s.pendingTheirsId, isNull);

    final res = await db.select(db.pendingResolutions).get();
    expect(res, isEmpty);

    expect(api.resolveAttributionCalls.single.decision,
        AttributionDecision.keepTheirs);
  });

  test('force_overwrite → submission flipped to uploaded', () async {
    await seedResolve(AttributionDecision.forceOverwrite.wire);
    await worker.drain();

    final s = await currentSubmission();
    expect(s.syncStatus, 'uploaded');
    expect(s.pendingTheirsId, isNull);

    expect(api.resolveAttributionCalls.single.decision,
        AttributionDecision.forceOverwrite);
  });
}
