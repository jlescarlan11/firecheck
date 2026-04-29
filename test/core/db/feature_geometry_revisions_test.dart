import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/map/reshape/data/feature_geometry_revisions_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late FeatureGeometryRevisionsRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = FeatureGeometryRevisionsRepository(db);

    // Seed one assignment + one feature so the FK on revisions is satisfied
    // and the geometry update has something to update.
    await db.into(db.assignments).insert(
      AssignmentsCompanion.insert(
        id: 'a1',
        enumeratorId: 'e1',
        campaignId: 'c1',
        boundaryPolygonGeojson: '{}',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await db.into(db.features).insert(
      FeaturesCompanion.insert(
        id: 'f1',
        assignmentId: 'a1',
        featureType: 'building',
        geometryGeojson: '{"type":"Polygon","coordinates":[[[0,0],[1,0],[0,1],[0,0]]]}',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    );
  });

  tearDown(() => db.close());

  test('saveReshape writes feature update + revision row + sync_job atomically', () async {
    const newGeojson = '{"type":"Polygon","coordinates":[[[0,0],[2,0],[0,2],[0,0]]]}';

    await repo.saveReshape(
      revisionId: 'r1',
      featureId: 'f1',
      prevGeojson: '{"type":"Polygon","coordinates":[[[0,0],[1,0],[0,1],[0,0]]]}',
      newGeojson: newGeojson,
      editedBy: 'e1',
      editedAt: DateTime.utc(2026, 4, 29, 12, 0),
      overrideReason: null,
    );

    final feature = await (db.select(db.features)
          ..where((t) => t.id.equals('f1')))
        .getSingle();
    expect(feature.geometryGeojson, newGeojson);

    final revisions = await db.select(db.featureGeometryRevisions).get();
    expect(revisions, hasLength(1));
    expect(revisions.first.id, 'r1');
    expect(revisions.first.syncStatus, 'ready_to_upload');
    expect(revisions.first.overrideReason, isNull);

    final jobs = await db.select(db.syncJobs).get();
    expect(jobs, hasLength(1));
    expect(jobs.first.entityType, 'feature_geometry_update');
    expect(jobs.first.entityId, 'r1');
    expect(jobs.first.status, 'pending');
  });

  test('saveReshape persists overrideReason when provided', () async {
    await repo.saveReshape(
      revisionId: 'r2',
      featureId: 'f1',
      prevGeojson: '{"type":"Polygon","coordinates":[[[0,0],[1,0],[0,1],[0,0]]]}',
      newGeojson:  '{"type":"Polygon","coordinates":[[[0,0],[2,0],[0,2],[0,0]]]}',
      editedBy: 'e1',
      editedAt: DateTime.utc(2026, 4, 29, 12, 0),
      overrideReason: 'corner visible from sidewalk',
    );

    final revisions = await db.select(db.featureGeometryRevisions).get();
    expect(revisions.first.overrideReason, 'corner visible from sidewalk');
  });

  test('getById returns the revision', () async {
    await repo.saveReshape(
      revisionId: 'r3',
      featureId: 'f1',
      prevGeojson: '{"type":"Polygon","coordinates":[[[0,0],[1,0],[0,1],[0,0]]]}',
      newGeojson:  '{"type":"Polygon","coordinates":[[[0,0],[2,0],[0,2],[0,0]]]}',
      editedBy: 'e1',
      editedAt: DateTime.utc(2026, 4, 29, 12, 0),
      overrideReason: null,
    );

    final found = await repo.getById('r3');
    expect(found, isNotNull);
    expect(found!.featureId, 'f1');
  });

  test('saveReshape rolls back all writes when revision insert fails', () async {
    // Pre-insert a row with revisionId='r4' so the second write throws a UNIQUE constraint.
    await db.into(db.featureGeometryRevisions).insert(
          FeatureGeometryRevisionsCompanion.insert(
            id: 'r4',
            featureId: 'f1',
            prevGeojson: '{}',
            newGeojson: '{}',
            editedBy: 'e1',
            editedAt: DateTime.utc(2026, 4, 29),
            createdAt: DateTime.utc(2026, 4, 29),
          ),
        );

    final originalGeo = (await (db.select(db.features)
              ..where((t) => t.id.equals('f1')))
            .getSingle())
        .geometryGeojson;

    await expectLater(
      repo.saveReshape(
        revisionId: 'r4', // collides on PK
        featureId: 'f1',
        prevGeojson: '{"type":"Polygon","coordinates":[[[0,0],[1,0],[0,1],[0,0]]]}',
        newGeojson:  '{"type":"Polygon","coordinates":[[[0,0],[3,0],[0,3],[0,0]]]}',
        editedBy: 'e1',
        editedAt: DateTime.utc(2026, 4, 29, 13),
        overrideReason: null,
      ),
      throwsA(anything),
    );

    // features.geometry_geojson must NOT have been updated.
    final feature = await (db.select(db.features)
          ..where((t) => t.id.equals('f1')))
        .getSingle();
    expect(feature.geometryGeojson, originalGeo);

    // No sync_job inserted from the failed call.
    final jobs = await db.select(db.syncJobs).get();
    expect(jobs, isEmpty);

    // Only the pre-seeded revision row remains.
    final revs = await db.select(db.featureGeometryRevisions).get();
    expect(revs, hasLength(1));
    expect(revs.first.id, 'r4');
  });

  test('markSynced flips syncStatus to uploaded', () async {
    await repo.saveReshape(
      revisionId: 'r5',
      featureId: 'f1',
      prevGeojson: '{"type":"Polygon","coordinates":[[[0,0],[1,0],[0,1],[0,0]]]}',
      newGeojson:  '{"type":"Polygon","coordinates":[[[0,0],[2,0],[0,2],[0,0]]]}',
      editedBy: 'e1',
      editedAt: DateTime.utc(2026, 4, 29),
      overrideReason: null,
    );

    await repo.markSynced('r5');
    final r = await repo.getById('r5');
    expect(r!.syncStatus, 'uploaded');
  });

  test('markFailed flips syncStatus to failed', () async {
    await repo.saveReshape(
      revisionId: 'r6',
      featureId: 'f1',
      prevGeojson: '{"type":"Polygon","coordinates":[[[0,0],[1,0],[0,1],[0,0]]]}',
      newGeojson:  '{"type":"Polygon","coordinates":[[[0,0],[2,0],[0,2],[0,0]]]}',
      editedBy: 'e1',
      editedAt: DateTime.utc(2026, 4, 29),
      overrideReason: null,
    );

    await repo.markFailed('r6');
    final r = await repo.getById('r6');
    expect(r!.syncStatus, 'failed');
  });
}
