import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/sync_jobs_repository.dart';
import 'package:firecheck/core/sync/domain/sync_entity_type.dart';
import 'package:firecheck/core/sync/domain/sync_job_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SyncJobsRepository repo;
  final now = DateTime(2026, 4, 26, 12);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = SyncJobsRepository(db);
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
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> insertJob({
    required String id,
    required String entityType,
    required String entityId,
    String status = 'pending',
    String? blocksOn,
    DateTime? nextRetry,
    int attempts = 0,
    Duration createdAtOffset = Duration.zero,
  }) async {
    await db.into(db.syncJobs).insert(SyncJobsCompanion.insert(
          id: id,
          entityType: entityType,
          entityId: entityId,
          status: Value(status),
          blocksOnSubmissionId: Value(blocksOn),
          nextRetryAt: Value(nextRetry),
          attempts: Value(attempts),
          createdAt: now.add(createdAtOffset),
        ),);
  }

  test('claimUpToN returns up to N pending jobs and marks them in_progress',
      () async {
    await insertJob(id: 'j1', entityType: 'submission', entityId: 's1');
    final claimed = await repo.claimUpToN(3, now: now);
    expect(claimed, hasLength(1));
    expect(claimed.first.id, 'j1');
    final reread = await (db.select(db.syncJobs)
          ..where((t) => t.id.equals('j1')))
        .getSingle();
    expect(reread.status, SyncJobStatus.inProgress);
  });

  test('claimUpToN respects next_retry_at (skips future-scheduled jobs)',
      () async {
    await insertJob(
      id: 'j1',
      entityType: 'submission',
      entityId: 's1',
      nextRetry: now.add(const Duration(minutes: 5)),
    );
    final claimed = await repo.claimUpToN(3, now: now);
    expect(claimed, isEmpty);
  });

  test('claimUpToN claims a job whose next_retry_at has elapsed', () async {
    await insertJob(
      id: 'j1',
      entityType: 'submission',
      entityId: 's1',
      nextRetry: now.subtract(const Duration(minutes: 1)),
    );
    final claimed = await repo.claimUpToN(3, now: now);
    expect(claimed, hasLength(1));
  });

  test('claimUpToN orders submission jobs first, then by created_at',
      () async {
    await insertJob(
        id: 'j-photo', entityType: 'photo', entityId: 'p1',);
    await insertJob(
        id: 'j-sub',
        entityType: 'submission',
        entityId: 's1',
        createdAtOffset: const Duration(seconds: 1),);
    final claimed = await repo.claimUpToN(2, now: now);
    expect(claimed.map((j) => j.id).toList(), ['j-sub', 'j-photo']);
  });

  test('claimUpToN blocks a photo job whose parent submission is not uploaded',
      () async {
    await db.into(db.photos).insert(PhotosCompanion.insert(
          id: 'ph1',
          submissionId: 's1',
          localPath: '/tmp/x.jpg',
          capturedAt: now,
          createdAt: now,
        ),);
    await insertJob(
        id: 'j-photo',
        entityType: 'photo',
        entityId: 'ph1',
        blocksOn: 's1',);
    final claimed = await repo.claimUpToN(3, now: now);
    expect(claimed, isEmpty);
  });

  test('claimUpToN unblocks a photo job once parent submission is uploaded',
      () async {
    await db.into(db.photos).insert(PhotosCompanion.insert(
          id: 'ph1',
          submissionId: 's1',
          localPath: '/tmp/x.jpg',
          capturedAt: now,
          createdAt: now,
        ),);
    await insertJob(
        id: 'j-photo',
        entityType: 'photo',
        entityId: 'ph1',
        blocksOn: 's1',);
    await (db.update(db.submissions)..where((t) => t.id.equals('s1'))).write(
        const SubmissionsCompanion(syncStatus: Value('uploaded'),),);
    final claimed = await repo.claimUpToN(3, now: now);
    expect(claimed, hasLength(1));
    expect(claimed.first.id, 'j-photo');
  });

  test('markSuccess transitions to success', () async {
    await insertJob(id: 'j1', entityType: 'submission', entityId: 's1');
    await repo.markSuccess('j1');
    final r = await (db.select(db.syncJobs)..where((t) => t.id.equals('j1')))
        .getSingle();
    expect(r.status, SyncJobStatus.success);
  });

  test('markPendingRetry advances attempts + sets next_retry_at + lastError',
      () async {
    await insertJob(id: 'j1', entityType: 'submission', entityId: 's1');
    final scheduled = now.add(const Duration(seconds: 30));
    await repo.markPendingRetry(
      'j1',
      attempts: 1,
      lastError: '500 error',
      nextRetryAt: scheduled,
    );
    final r = await (db.select(db.syncJobs)..where((t) => t.id.equals('j1')))
        .getSingle();
    expect(r.status, SyncJobStatus.pending);
    expect(r.attempts, 1);
    expect(r.nextRetryAt, scheduled);
    expect(r.lastError, '500 error');
  });

  test('markDead transitions to dead', () async {
    await insertJob(id: 'j1', entityType: 'submission', entityId: 's1');
    await repo.markDead('j1', error: '4xx', attempts: 5);
    final r = await (db.select(db.syncJobs)..where((t) => t.id.equals('j1')))
        .getSingle();
    expect(r.status, SyncJobStatus.dead);
    expect(r.attempts, 5);
    expect(r.lastError, '4xx');
  });

  test('findByEntity returns existing job or null', () async {
    expect(
        await repo.findByEntity(SyncEntityType.submission, 's1'), isNull,);
    await insertJob(id: 'j1', entityType: 'submission', entityId: 's1');
    final found = await repo.findByEntity(SyncEntityType.submission, 's1');
    expect(found, isNotNull);
    expect(found!.id, 'j1');
  });
}
