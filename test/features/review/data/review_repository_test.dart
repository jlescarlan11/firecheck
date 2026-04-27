import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/review/data/review_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ReviewRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ReviewRepository(db);
  });
  tearDown(() async => db.close());

  Future<void> seedAssignmentAndFeature() async {
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
          id: 'a-1',
          enumeratorId: 'e-1',
          campaignId: 'c-1',
          boundaryPolygonGeojson: '{}',
          createdAt: DateTime(2026, 4, 27),
        ),);
    await db.into(db.features).insert(FeaturesCompanion.insert(
          id: 'f-1',
          assignmentId: 'a-1',
          featureType: 'building',
          geometryGeojson: '{}',
          createdAt: DateTime(2026, 4, 27),
        ),);
  }

  test('emits a snapshot containing seeded features', () async {
    await seedAssignmentAndFeature();

    final first = await repo.streamForAssignment('a-1').first;
    expect(first.features, hasLength(1));
    expect(first.features.first.id, 'f-1');
    expect(first.submissions, isEmpty);
    expect(first.deadJobs, isEmpty);
  });

  test('re-emits when a submission is added', () async {
    await seedAssignmentAndFeature();
    final emitted = <int>[];
    final sub = repo.streamForAssignment('a-1').listen((data) {
      emitted.add(data.submissions.length);
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await db.into(db.submissions).insert(SubmissionsCompanion.insert(
          id: 's-1',
          featureId: 'f-1',
          submittedBy: const Value('u-1'),
          createdAt: DateTime(2026, 4, 27),
          updatedAt: DateTime(2026, 4, 27),
        ),);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await sub.cancel();
    expect(emitted.last, 1);
  });

  test('photoCountsBySubmission counts photos per submission id', () async {
    await seedAssignmentAndFeature();
    await db.into(db.submissions).insert(SubmissionsCompanion.insert(
          id: 's-1',
          featureId: 'f-1',
          submittedBy: const Value('u-1'),
          createdAt: DateTime(2026, 4, 27),
          updatedAt: DateTime(2026, 4, 27),
        ),);
    await db.into(db.photos).insert(PhotosCompanion.insert(
          id: 'p-1',
          submissionId: 's-1',
          localPath: '/tmp/x.jpg',
          capturedAt: DateTime(2026, 4, 27),
          createdAt: DateTime(2026, 4, 27),
        ),);

    final snap = await repo.streamForAssignment('a-1').first;
    expect(snap.photoCountsBySubmission['s-1'], 1);
  });

  test('deadJobs surfaces only sync_jobs with status=dead for this assignment',
      () async {
    await seedAssignmentAndFeature();
    await db.into(db.submissions).insert(SubmissionsCompanion.insert(
          id: 's-1',
          featureId: 'f-1',
          submittedBy: const Value('u-1'),
          createdAt: DateTime(2026, 4, 27),
          updatedAt: DateTime(2026, 4, 27),
        ),);
    await db.into(db.syncJobs).insert(SyncJobsCompanion.insert(
          id: 'j-1',
          entityType: 'submission',
          entityId: 's-1',
          createdAt: DateTime(2026, 4, 27),
        ),);
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
