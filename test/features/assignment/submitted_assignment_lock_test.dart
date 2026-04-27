import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/data/submitted_assignment_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SubmittedAssignmentLock lock;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    lock = SubmittedAssignmentLock(db);
  });
  tearDown(() async => db.close());

  Future<void> seedAssignment({DateTime? submittedAt}) async {
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
          id: 'a-1',
          enumeratorId: 'e-1',
          campaignId: 'c-1',
          boundaryPolygonGeojson: '{}',
          createdAt: DateTime(2026, 4, 27),
          submittedAt: Value(submittedAt),
        ),);
    await db.into(db.features).insert(FeaturesCompanion.insert(
          id: 'f-1',
          assignmentId: 'a-1',
          featureType: 'building',
          geometryGeojson: '{}',
          createdAt: DateTime(2026, 4, 27),
        ),);
    await db.into(db.submissions).insert(SubmissionsCompanion.insert(
          id: 's-1',
          featureId: 'f-1',
          submittedBy: const Value('u-1'),
          createdAt: DateTime(2026, 4, 27),
          updatedAt: DateTime(2026, 4, 27),
        ),);
  }

  Future<void> addJob(String id, String status, {String entityType = 'submission', String entityId = 's-1'}) async {
    await db.into(db.syncJobs).insert(SyncJobsCompanion.insert(
          id: id,
          entityType: entityType,
          entityId: entityId,
          createdAt: DateTime(2026, 4, 27),
        ),);
    if (status != 'pending') {
      await (db.update(db.syncJobs)..where((t) => t.id.equals(id))).write(
        SyncJobsCompanion(status: Value(status)),
      );
    }
  }

  test('stamps submittedAt when no non-terminal jobs remain', () async {
    await seedAssignment();
    await addJob('j-1', 'success');

    final sub = lock.watchAndStamp('a-1').listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();

    final a = await (db.select(db.assignments)..where((t) => t.id.equals('a-1')))
        .getSingle();
    expect(a.submittedAt, isNotNull);
  });

  test('does NOT stamp when a pending submission job remains', () async {
    await seedAssignment();
    await addJob('j-1', 'pending');

    final sub = lock.watchAndStamp('a-1').listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();

    final a = await (db.select(db.assignments)..where((t) => t.id.equals('a-1')))
        .getSingle();
    expect(a.submittedAt, isNull);
  });

  test('does NOT stamp when a pending photo job remains', () async {
    await seedAssignment();
    await db.into(db.photos).insert(PhotosCompanion.insert(
          id: 'p-1',
          submissionId: 's-1',
          localPath: '/tmp/x.jpg',
          capturedAt: DateTime(2026, 4, 27),
          createdAt: DateTime(2026, 4, 27),
        ),);
    await addJob('j-1', 'success'); // submission job done
    await addJob('j-2', 'pending', entityType: 'photo', entityId: 'p-1');

    final sub = lock.watchAndStamp('a-1').listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();

    final a = await (db.select(db.assignments)..where((t) => t.id.equals('a-1')))
        .getSingle();
    expect(a.submittedAt, isNull);
  });

  test('does NOT stamp when a dead job remains', () async {
    await seedAssignment();
    await addJob('j-1', 'dead');

    final sub = lock.watchAndStamp('a-1').listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();

    final a = await (db.select(db.assignments)..where((t) => t.id.equals('a-1')))
        .getSingle();
    expect(a.submittedAt, isNull);
  });

  test('idempotent — does not overwrite existing submittedAt', () async {
    final original = DateTime(2026);
    await seedAssignment(submittedAt: original);
    await addJob('j-1', 'success');

    final sub = lock.watchAndStamp('a-1').listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();

    final a = await (db.select(db.assignments)..where((t) => t.id.equals('a-1')))
        .getSingle();
    expect(a.submittedAt, original);
  });
}
