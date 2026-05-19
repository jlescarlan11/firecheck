import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/domain/finalize_submission.dart';
import 'package:firecheck/core/sync/domain/sync_entity_type.dart';
import 'package:firecheck/core/sync/domain/sync_job_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late FinalizeSubmissionUseCase useCase;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    useCase = FinalizeSubmissionUseCase(db);
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
  });

  tearDown(() async => db.close());

  test('execute writes one submission sync_job + 0 photos when none exist',
      () async {
    final r = await useCase.execute('s1');
    expect(r.submissionId, 's1');
    expect(r.photoCount, 0);
    expect(r.newFeatureQueued, isFalse);

    final sub = await (db.select(db.submissions)
          ..where((t) => t.id.equals('s1')))
        .getSingle();
    expect(sub.syncStatus, 'queued');

    final jobs = await db.select(db.syncJobs).get();
    expect(jobs, hasLength(1));
    expect(jobs.first.entityType, SyncEntityType.attributionUpload);
    expect(jobs.first.entityId, 's1');
    expect(jobs.first.status, SyncJobStatus.pending);
  });

  test('execute writes a sync_job per photo with blocks_on_submission_id',
      () async {
    final now = DateTime.now();
    await db.into(db.photos).insert(PhotosCompanion.insert(
          id: 'ph1',
          submissionId: 's1',
          localPath: '/tmp/a.jpg',
          capturedAt: now,
          createdAt: now,
        ),);
    await db.into(db.photos).insert(PhotosCompanion.insert(
          id: 'ph2',
          submissionId: 's1',
          localPath: '/tmp/b.jpg',
          capturedAt: now,
          createdAt: now,
        ),);

    final r = await useCase.execute('s1');
    expect(r.photoCount, 2);

    final photoJobs = await (db.select(db.syncJobs)
          ..where((t) => t.entityType.equals(SyncEntityType.photo)))
        .get();
    expect(photoJobs, hasLength(2));
    expect(photoJobs.every((j) => j.blocksOnSubmissionId == 's1'), isTrue);
  });

  test('execute writes new_feature sync_job when feature.is_new=true',
      () async {
    await (db.update(db.features)..where((t) => t.id.equals('f1')))
        .write(const FeaturesCompanion(isNew: Value(true)));
    final r = await useCase.execute('s1');
    expect(r.newFeatureQueued, isTrue);
    final job = await (db.select(db.syncJobs)
          ..where((t) => t.entityType.equals(SyncEntityType.newFeatureUpload)))
        .getSingle();
    expect(job.entityId, 'f1');
  });

  test('execute is idempotent — calling twice does not duplicate jobs',
      () async {
    await useCase.execute('s1');
    await useCase.execute('s1');
    final jobs = await db.select(db.syncJobs).get();
    expect(jobs, hasLength(1));
  });
}
