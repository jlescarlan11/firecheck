import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:firecheck/features/new_feature/data/new_feature_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late AssignmentRepository repo;
  const boundary =
      '{"type":"Polygon","coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]]]}';
  Future<void> add(String id) => db.into(db.assignments).insertOnConflictUpdate(
        AssignmentsCompanion.insert(
            id: id,
            enumeratorId: 'me',
            campaignId: id,
            name: Value(id),
            boundaryPolygonGeojson: boundary,
            createdAt: DateTime.now()),
      );
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AssignmentRepository(db: db, userId: 'me');
    await add('cebu');
    await add('guadalupe');
  });
  tearDown(() => db.close());

  test('imports keep both maps and never select one implicitly', () async {
    expect(await repo.getCurrentAssignment(), isNull);
    expect(await repo.watchDownloadedAssignments().first, hasLength(2));
    await repo.selectAssignment('cebu');
    await add('guadalupe');
    expect((await repo.getCurrentAssignment())?.id, 'cebu');
    expect(await repo.watchDownloadedAssignments().first, hasLength(2));
  });

  test('selection is restored by a new repository and isolated by account',
      () async {
    await repo.selectAssignment('cebu');
    final other = AssignmentRepository(db: db, userId: 'other');
    expect(await other.getCurrentAssignment(), isNull);
    await other.selectAssignment('guadalupe');
    expect(
        (await AssignmentRepository(db: db, userId: 'me')
                .getCurrentAssignment())
            ?.id,
        'cebu');
    expect((await other.getCurrentAssignment())?.id, 'guadalupe');
    expect(await AssignmentRepository(db: db).getCurrentAssignment(), isNull);
    await expectLater(repo.selectAssignment('missing'), throwsStateError);
    expect((await repo.getCurrentAssignment())?.id, 'cebu');
  });

  test('selection stream changes independently of import order', () async {
    await repo.selectAssignment('guadalupe');
    final next =
        repo.watchCurrentAssignment().firstWhere((a) => a?.id == 'cebu');
    await repo.selectAssignment('cebu');
    expect((await next)?.id, 'cebu');
  });

  test(
      'save uses captured owner even after selection changes in overlapping areas',
      () async {
    await repo.selectAssignment('cebu');
    final owner = (await repo.getCurrentAssignment())!.id;
    await repo.selectAssignment('guadalupe');
    final feature = await NewFeatureRepository(db).createFeature(
      assignmentId: owner,
      featureType: 'building',
      geometryGeojson:
          '{"type":"Polygon","coordinates":[[[1,1],[2,1],[2,2],[1,1]]]}',
    );
    expect(feature.assignmentId, 'cebu');
  });

  test('outside and closed-map writes reject without inserting a feature',
      () async {
    final creator = NewFeatureRepository(db);
    await expectLater(
        creator.createFeature(
            assignmentId: 'cebu',
            featureType: 'point',
            geometryGeojson: '{"type":"Point","coordinates":[20,20]}'),
        throwsStateError);
    await (db.update(db.assignments)..where((t) => t.id.equals('cebu')))
        .write(const AssignmentsCompanion(closedRemotely: Value(true)));
    await expectLater(
        creator.createFeature(
            assignmentId: 'cebu',
            featureType: 'point',
            geometryGeojson: '{"type":"Point","coordinates":[2,2]}'),
        throwsStateError);
    expect(await db.select(db.features).get(), isEmpty);
    await repo.selectAssignment('guadalupe');
    expect((await repo.getCurrentAssignment())?.id, 'guadalupe');
  });
}
