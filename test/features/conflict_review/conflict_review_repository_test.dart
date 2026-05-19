import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/domain/resolution_decision.dart';
import 'package:firecheck/core/sync/domain/sync_entity_type.dart';
import 'package:firecheck/features/conflict_review/data/conflict_review_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ConflictReviewRepository repo;
  final now = DateTime.utc(2026, 5, 19, 10);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ConflictReviewRepository(db);
  });
  tearDown(() => db.close());

  Future<List<SyncJob>> jobs() =>
      (db.select(db.syncJobs)).get();

  test('queueAttributionDecision inserts pending_resolutions + sync_job',
      () async {
    await repo.queueAttributionDecision(
      submissionId: 's1',
      decision: AttributionDecision.keepTheirs,
      resolutionNote: 'duplicate',
    );

    final pr = await db.select(db.pendingResolutions).get();
    expect(pr, hasLength(1));
    expect(pr.first.targetId, 's1');
    expect(pr.first.kind, 'attribution');
    expect(pr.first.decision, 'keep_theirs');
    expect(pr.first.resolutionNote, 'duplicate');

    final js = await jobs();
    expect(js, hasLength(1));
    expect(js.first.entityType, SyncEntityType.attributionResolve);
    expect(js.first.entityId, 's1');
    expect(js.first.status, 'pending');
  });

  test('re-queue overwrites decision and resets the job', () async {
    await repo.queueAttributionDecision(
      submissionId: 's1',
      decision: AttributionDecision.keepTheirs,
    );
    // Simulate a stalled job that was marked failed.
    await (db.update(db.syncJobs)
          ..where(
            (t) => t.entityType.equals(SyncEntityType.attributionResolve),
          ))
        .write(
      SyncJobsCompanion(
        status: const Value('dead'),
        attempts: const Value(3),
        lastError: const Value('boom'),
        nextRetryAt: Value(now.add(const Duration(hours: 1))),
      ),
    );

    await repo.queueAttributionDecision(
      submissionId: 's1',
      decision: AttributionDecision.forceOverwrite,
    );

    final pr = await db.select(db.pendingResolutions).get();
    expect(pr.single.decision, 'force_overwrite',
        reason: 'changed-mind decision overwrites the prior queued one');

    final j = (await jobs()).single;
    expect(j.status, 'pending');
    expect(j.attempts, 0);
    expect(j.lastError, isNull);
    expect(j.nextRetryAt, isNull);
  });

  test('queueDedupDecision routes via newFeatureResolve', () async {
    await repo.queueDedupDecision(
      featureId: 'f1',
      decision: DedupDecision.discardMine,
    );

    final pr = await db.select(db.pendingResolutions).get();
    expect(pr.single.kind, 'new_feature');
    expect(pr.single.decision, 'discard_mine');

    final j = (await jobs()).single;
    expect(j.entityType, SyncEntityType.newFeatureResolve);
    expect(j.entityId, 'f1');
  });
}
