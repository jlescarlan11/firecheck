import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/home/data/progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ProgressRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ProgressRepository(db);
  });

  tearDown(() async => db.close());

  test('watchProgress emits empty snapshot when DB is empty', () async {
    final snap = await repo.watchProgress().first;
    expect(snap.totalFeatures, 0);
    expect(snap.completedFeatures, 0);
    expect(snap.queuedJobs, 0);
    expect(snap.failedJobs, 0);
    expect(snap.deadJobs, 0);
  });

  test('watchProgress reflects feature counts by status', () async {
    final now = DateTime.now();
    await db.into(db.features).insert(FeaturesCompanion.insert(
          id: 'f1',
          assignmentId: 'a1',
          featureType: 'building',
          geometryGeojson: '{}',
          createdAt: now,
          status: const Value('complete'),
        ));
    await db.into(db.features).insert(FeaturesCompanion.insert(
          id: 'f2',
          assignmentId: 'a1',
          featureType: 'building',
          geometryGeojson: '{}',
          createdAt: now,
          status: const Value('in_progress'),
        ));
    await db.into(db.features).insert(FeaturesCompanion.insert(
          id: 'f3',
          assignmentId: 'a1',
          featureType: 'road',
          geometryGeojson: '{}',
          createdAt: now,
        ));

    final snap = await repo.watchProgress().first;
    expect(snap.totalFeatures, 3);
    expect(snap.completedFeatures, 1);
    expect(snap.inProgressFeatures, 1);
  });

  test('watchProgress reflects sync_jobs counts by status', () async {
    final now = DateTime.now();
    await db.into(db.syncJobs).insert(SyncJobsCompanion.insert(
          id: 's1',
          entityType: 'submission',
          entityId: 'x',
          createdAt: now,
          status: const Value('pending'),
        ));
    await db.into(db.syncJobs).insert(SyncJobsCompanion.insert(
          id: 's2',
          entityType: 'submission',
          entityId: 'y',
          createdAt: now,
          status: const Value('failed'),
        ));
    await db.into(db.syncJobs).insert(SyncJobsCompanion.insert(
          id: 's3',
          entityType: 'photo',
          entityId: 'z',
          createdAt: now,
          status: const Value('dead'),
        ));

    final snap = await repo.watchProgress().first;
    expect(snap.queuedJobs, 1);
    expect(snap.failedJobs, 1);
    expect(snap.deadJobs, 1);
  });
}
