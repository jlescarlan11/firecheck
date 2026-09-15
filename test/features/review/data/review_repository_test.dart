import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/review/data/review_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firecheck/features/review/domain/review_validator.dart';

void main() {
  late AppDatabase db;
  late ReviewRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ReviewRepository(db);
  });
  tearDown(() async => db.close());

  Future<void> seedAssignmentAndFeature() async {
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a-1',
            enumeratorId: 'e-1',
            campaignId: 'c-1',
            boundaryPolygonGeojson: '{}',
            createdAt: DateTime(2026, 4, 27),
          ),
        );
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f-1',
            assignmentId: 'a-1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: DateTime(2026, 4, 27),
          ),
        );
  }

  test('excludes untouched assigned features', () async {
    await seedAssignmentAndFeature();

    final first = await repo.streamForAssignment('a-1').first;
    expect(first.features, isEmpty);
    expect(first.submissions, isEmpty);
    expect(first.deadJobs, isEmpty);
  });

  test('excludes a draft created by opening a feature, then includes edits',
      () async {
    await seedAssignmentAndFeature();
    final now = DateTime(2026, 4, 27);
    await db.into(db.submissions).insert(SubmissionsCompanion.insert(
          id: 's-1',
          featureId: 'f-1',
          createdAt: now,
          updatedAt: now,
        ));
    expect((await repo.streamForAssignment('a-1').first).features, isEmpty);

    await db.into(db.buildingAttributes).insert(
          BuildingAttributesCompanion.insert(
            submissionId: 's-1',
            buildingName: const Value('Saved name'),
          ),
        );
    final snapshot = await repo.streamForAssignment('a-1').first;
    expect(snapshot.features.single.id, 'f-1');
    final state = buildReviewState(snapshot);
    expect(state.summary.incompleteFeatures, 1);
    expect(state.warnings.single.featureId, 'f-1');
  });

  test('includes new features before a survey is saved', () async {
    await seedAssignmentAndFeature();
    await db.update(db.features).write(
          const FeaturesCompanion(isNew: Value(true)),
        );
    final state = buildReviewState(await repo.streamForAssignment('a-1').first);
    expect(state.summary.totalFeatures, 1);
    expect(state.summary.newFeaturesAdded, 1);
  });

  test('1428 assignments only review the two edited features', () async {
    await seedAssignmentAndFeature();
    final now = DateTime(2026, 4, 27);
    await db.batch((batch) {
      batch.insertAll(db.features, [
        for (var i = 2; i <= 1428; i++)
          FeaturesCompanion.insert(
            id: 'f-$i',
            assignmentId: 'a-1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: now,
          ),
        FeaturesCompanion.insert(
          id: 'other',
          assignmentId: 'a-2',
          featureType: 'building',
          isNew: const Value(true),
          geometryGeojson: '{}',
          createdAt: now,
        ),
      ]);
      batch.insertAll(db.submissions, [
        for (var i = 1; i <= 2; i++)
          SubmissionsCompanion.insert(
            id: 's-$i',
            featureId: 'f-$i',
            syncStatus: const Value('ready_to_upload'),
            createdAt: now,
            updatedAt: now,
          ),
      ]);
    });
    final snapshot = await repo.streamForAssignment('a-1').first;
    expect(snapshot.features.map((f) => f.id), unorderedEquals(['f-1', 'f-2']));
    expect(snapshot.submissions, hasLength(2));
    final state = buildReviewState(snapshot);
    expect(state.summary.totalFeatures, 2);
    expect(state.warnings, isEmpty);
    expect(state.blockers, hasLength(4));
  });

  test('merged-away features are excluded from review validation', () async {
    await seedAssignmentAndFeature();
    await db.update(db.features).write(
          const FeaturesCompanion(mergedIntoId: Value('survivor')),
        );
    final snapshot = await repo.streamForAssignment('a-1').first;
    expect(snapshot.features, isEmpty);
    expect(snapshot.submissions, isEmpty);
  });

  test('re-emits when a submission is finalized', () async {
    await seedAssignmentAndFeature();
    final emitted = <int>[];
    final sub = repo.streamForAssignment('a-1').listen((data) {
      emitted.add(data.submissions.length);
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await db.into(db.submissions).insert(
          SubmissionsCompanion.insert(
            id: 's-1',
            featureId: 'f-1',
            submittedBy: const Value('u-1'),
            syncStatus: const Value('ready_to_upload'),
            createdAt: DateTime(2026, 4, 27),
            updatedAt: DateTime(2026, 4, 27),
          ),
        );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await sub.cancel();
    expect(emitted.last, 1);
  });

  test('photoCountsBySubmission counts photos per submission id', () async {
    await seedAssignmentAndFeature();
    await db.into(db.submissions).insert(
          SubmissionsCompanion.insert(
            id: 's-1',
            featureId: 'f-1',
            submittedBy: const Value('u-1'),
            createdAt: DateTime(2026, 4, 27),
            updatedAt: DateTime(2026, 4, 27),
          ),
        );
    await db.into(db.photos).insert(
          PhotosCompanion.insert(
            id: 'p-1',
            submissionId: 's-1',
            localPath: '/tmp/x.jpg',
            capturedAt: DateTime(2026, 4, 27),
            createdAt: DateTime(2026, 4, 27),
          ),
        );

    final snap = await repo.streamForAssignment('a-1').first;
    expect(snap.photoCountsBySubmission['s-1'], 1);
  });

  test('deadJobs surfaces only sync_jobs with status=dead for this assignment',
      () async {
    await seedAssignmentAndFeature();
    await db.into(db.submissions).insert(
          SubmissionsCompanion.insert(
            id: 's-1',
            featureId: 'f-1',
            submittedBy: const Value('u-1'),
            createdAt: DateTime(2026, 4, 27),
            updatedAt: DateTime(2026, 4, 27),
          ),
        );
    await db.into(db.syncJobs).insert(
          SyncJobsCompanion.insert(
            id: 'j-1',
            entityType: 'submission',
            entityId: 's-1',
            createdAt: DateTime(2026, 4, 27),
          ),
        );
    await (db.update(db.syncJobs)..where((t) => t.id.equals('j-1'))).write(
      const SyncJobsCompanion(
        status: Value('dead'),
        attempts: Value(5),
        lastError: Value('Network error'),
      ),
    );

    final snap = await repo.streamForAssignment('a-1').first;
    expect(snap.deadJobs, hasLength(1));
    expect(snap.deadJobs.first.jobId, 'j-1');
    expect(snap.deadJobs.first.attempts, 5);
  });
}
