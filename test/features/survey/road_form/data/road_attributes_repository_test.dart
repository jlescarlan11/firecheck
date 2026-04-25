import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/survey/road_form/data/road_attributes_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late RoadAttributesRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = RoadAttributesRepository(db);
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
            featureType: 'road',
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

  test('upsert round-trips JSON-encoded roadFeatures list', () async {
    await repo.upsertForSubmission(
      's1',
      RoadAttributesCompanion.insert(
        submissionId: 's1',
        roadName: const Value('Mango Ave'),
        widthMeters: const Value(4.5),
        roadFeaturesJson: const Value('["vendor","pedestrian"]'),
      ),
    );
    final found = await repo.findBySubmission('s1');
    expect(found, isNotNull);
    expect(found!.roadName, 'Mango Ave');
    expect(found.widthMeters, 4.5);
    expect(
      RoadAttributesRepository.decodeStringList(found.roadFeaturesJson),
      ['vendor', 'pedestrian'],
    );
  });

  test('upsert overwrites existing row', () async {
    await repo.upsertForSubmission(
      's1',
      RoadAttributesCompanion.insert(
        submissionId: 's1',
        roadName: const Value('Mango Ave'),
      ),
    );
    await repo.upsertForSubmission(
      's1',
      RoadAttributesCompanion.insert(
        submissionId: 's1',
        roadName: const Value('Mango Avenue'),
        widthMeters: const Value(6),
      ),
    );
    final found = await repo.findBySubmission('s1');
    expect(found!.roadName, 'Mango Avenue');
    expect(found.widthMeters, 6);
  });

  test('decodeStringList handles empty + single + many', () {
    expect(RoadAttributesRepository.decodeStringList('[]'), isEmpty);
    expect(RoadAttributesRepository.decodeStringList('["a"]'), ['a']);
    expect(
      RoadAttributesRepository.decodeStringList('["a","b","c"]'),
      ['a', 'b', 'c'],
    );
  });
}
