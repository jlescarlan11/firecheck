import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/survey/building_form/data/submission_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SubmissionRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = SubmissionRepository(db);
    // Seed a feature so submissions.feature_id has a parent. (PRAGMA
    // foreign_keys is on, but Drift tables don't currently declare FK
    // constraints — still, treating the FK chain correctly keeps these
    // tests honest about the data model.)
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f1',
            assignmentId: 'a1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: DateTime.now(),
          ),
        );
  });

  tearDown(() async => db.close());

  test('ensureDraftForFeature is idempotent', () async {
    final a = await repo.ensureDraftForFeature(
      featureId: 'f1',
      enumeratorId: 'u1',
    );
    final b = await repo.ensureDraftForFeature(
      featureId: 'f1',
      enumeratorId: 'u1',
    );
    expect(a.id, b.id);
    expect(await repo.countSubmissionsForFeature('f1'), 1);
  });

  test('createAdditionalSubmission always creates a new row', () async {
    await repo.ensureDraftForFeature(
      featureId: 'f1',
      enumeratorId: 'u1',
    );
    await repo.createAdditionalSubmission(
      featureId: 'f1',
      enumeratorId: 'u1',
    );
    expect(await repo.countSubmissionsForFeature('f1'), 2);
  });

  test('updateOverrideReason persists the value', () async {
    final s = await repo.ensureDraftForFeature(
      featureId: 'f1',
      enumeratorId: 'u1',
    );
    await repo.updateOverrideReason(s.id, 'polygon misplaced');
    final reloaded = (await db.select(db.submissions).get()).single;
    expect(reloaded.overrideReason, 'polygon misplaced');
  });

  test('updateDoesNotExist + markStatus + delete', () async {
    final s = await repo.ensureDraftForFeature(
      featureId: 'f1',
      enumeratorId: 'u1',
    );
    await repo.updateDoesNotExist(s.id, doesNotExist: true);
    await repo.markStatus(s.id, 'ready_to_upload');
    final reloaded = (await db.select(db.submissions).get()).single;
    expect(reloaded.doesNotExist, isTrue);
    expect(reloaded.syncStatus, 'ready_to_upload');

    await repo.deleteSubmission(s.id);
    expect(await db.select(db.submissions).get(), isEmpty);
  });

  test('ensureDraftForFeature stores UUID enumeratorId in submittedBy', () async {
    const uuid = '550e8400-e29b-41d4-a716-446655440000';
    final submission = await repo.ensureDraftForFeature(
      featureId: 'f1',
      enumeratorId: uuid,
    );
    expect(submission.submittedBy, uuid);
  });
}
