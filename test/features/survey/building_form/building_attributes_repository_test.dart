import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/survey/building_form/data/building_attributes_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late BuildingAttributesRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = BuildingAttributesRepository(db);
    final now = DateTime.now();
    // Seed parent chain so building_attributes.submission_id has a valid
    // parent submission → feature path.
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

  test('upsert then watch returns the row', () async {
    await repo.upsertForSubmission(
      submissionId: 's1',
      buildingName: 'Hall',
      ra9514Type: 'A',
      storeys: 3,
      material: 'Concrete',
      costEstimateRange: '500k–1M',
      fireFightingFacilities: ['Extinguisher', 'Smoke alarm'],
      fireLoad: ['Wood furniture', 'Fabric'],
    );
    final row = await repo.watchForSubmission('s1').first;
    expect(row, isNotNull);
    expect(row!.buildingName, 'Hall');
    expect(row.storeys, 3);
    expect(
      BuildingAttributesRepository.decodeStringList(
        row.fireFightingFacilitiesJson,
      ),
      ['Extinguisher', 'Smoke alarm'],
    );
  });

  test('upsert overwrites existing row', () async {
    await repo.upsertForSubmission(submissionId: 's1', storeys: 1);
    await repo.upsertForSubmission(submissionId: 's1', storeys: 5);
    final row = await repo.watchForSubmission('s1').first;
    expect(row!.storeys, 5);
  });

  test('watchForSubmission emits null for unknown submission', () async {
    expect(await repo.watchForSubmission('nope').first, isNull);
  });
}
