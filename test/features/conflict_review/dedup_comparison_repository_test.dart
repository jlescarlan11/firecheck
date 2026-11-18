import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/domain/resolution_decision.dart';
import 'package:firecheck/features/conflict_review/data/conflict_review_repository.dart';
import 'package:firecheck/features/conflict_review/data/dedup_comparison_repository.dart';
import 'package:firecheck/features/conflict_review/domain/dedup_comparison.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dedup_test_fixture.dart';

void main() {
  late AppDatabase db;
  late DedupComparisonRepository repository;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedComparison(db);
    repository = DedupComparisonRepository(db);
  });
  tearDown(() => db.close());
  Future<DedupComparison?> load({
    String account = 'u',
    String assignment = 'a',
  }) =>
      repository.load(
        featureId: 'mine',
        assignmentId: assignment,
        accountId: account,
      );
  test('offline local geometry resolves stable IDs in selected account/map',
      () async {
    final result = (await load())!;
    expect(result.mine.id, 'mine');
    expect(result.existing.id, 'existing');
    expect(await load(account: 'someone'), isNull);
    expect(await load(assignment: 'other'), isNull);
  });
  test(
      'missing, cross-assignment, malformed and superseded counterpart unavailable',
      () async {
    await (db.update(db.features)..where((t) => t.id.equals('existing')))
        .write(const FeaturesCompanion(assignmentId: Value('other')));
    expect(await load(), isNull);
    await (db.update(db.features)..where((t) => t.id.equals('existing'))).write(
      const FeaturesCompanion(
        assignmentId: Value('a'),
        geometryGeojson: Value('bad'),
      ),
    );
    expect(await load(), isNull);
    await (db.update(db.features)..where((t) => t.id.equals('existing'))).write(
      const FeaturesCompanion(
        geometryGeojson: Value(polygon),
        mergedIntoId: Value('new'),
      ),
    );
    expect(await load(), isNull);
  });
  test('remote tombstone overrides older local geometry', () async {
    final now = DateTime.utc(2026);
    await db.into(db.remoteNewFeaturesCache).insert(
          RemoteNewFeaturesCacheCompanion.insert(
            id: 'existing',
            assignmentId: 'a',
            featureType: 'building',
            geometryGeojson: polygon,
            centroidLat: 10,
            centroidLng: 123,
            submittedAt: now,
            updatedAt: now,
            cachedAt: now,
            supersededAt: Value(now),
          ),
        );
    expect(await load(), isNull);
  });
  test('queue rejects a stale comparison atomically without pending work',
      () async {
    final comparison = (await repository.load(
      featureId: 'mine',
      assignmentId: 'a',
      accountId: 'u',
    ))!;
    await db.delete(db.assignmentSelections).go();
    await expectLater(
      repository.queueDecision(
        comparison: comparison,
        decision: DedupDecision.replaceTheirs,
        resolutions: ConflictReviewRepository(db),
      ),
      throwsStateError,
    );
    expect(await db.select(db.pendingResolutions).get(), isEmpty);
    expect(await db.select(db.syncJobs).get(), isEmpty);
  });
  test('constant wakeup query reacts to feature, cache and selection updates',
      () async {
    final events = StreamIterator(
      repository.watch(featureId: 'mine', assignmentId: 'a', accountId: 'u'),
    );
    Future<void> next() async {
      expect(
        await events.moveNext().timeout(const Duration(seconds: 2)),
        isTrue,
      );
    }

    await next();
    expect(events.current, isNotNull);
    await (db.update(db.features)..where((t) => t.id.equals('existing')))
        .write(const FeaturesCompanion(geometryGeojson: Value('bad')));
    await next();
    expect(events.current, isNull);
    await (db.update(db.features)..where((t) => t.id.equals('existing')))
        .write(const FeaturesCompanion(geometryGeojson: Value(polygon)));
    await next();
    expect(events.current, isNotNull);
    final now = DateTime.utc(2026);
    await db.into(db.remoteNewFeaturesCache).insert(
          RemoteNewFeaturesCacheCompanion.insert(
            id: 'existing',
            assignmentId: 'a',
            featureType: 'building',
            geometryGeojson: polygon,
            centroidLat: 10,
            centroidLng: 123,
            submittedAt: now,
            updatedAt: now,
            cachedAt: now,
            supersededAt: Value(now),
          ),
        );
    await next();
    expect(events.current, isNull);
    await db.delete(db.remoteNewFeaturesCache).go();
    await next();
    expect(events.current, isNotNull);
    await db.delete(db.assignmentSelections).go();
    await next();
    expect(events.current, isNull);
    await events.cancel();
  });
  test('account context lost during lookup prevents durable queue', () async {
    final comparison = (await repository.load(
      featureId: 'mine',
      assignmentId: 'a',
      accountId: 'u',
    ))!;
    await expectLater(
      repository.queueDecision(
        comparison: comparison,
        decision: DedupDecision.replaceTheirs,
        resolutions: ConflictReviewRepository(db),
        isCurrentContext: () => false,
      ),
      throwsStateError,
    );
    expect(await db.select(db.pendingResolutions).get(), isEmpty);
  });
  test('valid compared decision reuses durable resolution transaction',
      () async {
    final comparison = (await repository.load(
      featureId: 'mine',
      assignmentId: 'a',
      accountId: 'u',
    ))!;
    await repository.queueDecision(
      comparison: comparison,
      decision: DedupDecision.discardMine,
      resolutions: ConflictReviewRepository(db),
    );
    expect(
      (await db.select(db.pendingResolutions).get()).single.decision,
      'discard_mine',
    );
    expect((await db.select(db.syncJobs).get()).single.entityId, 'mine');
  });
  test('selection switch and closed assignment invalidate comparison',
      () async {
    await db.delete(db.assignmentSelections).go();
    expect(await load(), isNull);
    await db.into(db.assignmentSelections).insert(
          AssignmentSelectionsCompanion.insert(
            userId: 'u',
            assignmentId: 'a',
            selectedAt: DateTime.utc(2026),
          ),
        );
    await db
        .update(db.assignments)
        .write(const AssignmentsCompanion(closedRemotely: Value(true)));
    expect(await load(), isNull);
  });
}
