import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/map/data/feature_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late FeatureRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = FeatureRepository(db);
  });

  tearDown(() async => db.close());

  test('watchFeaturesForAssignment emits empty list initially', () async {
    final list = await repo.watchFeaturesForAssignment('a1').first;
    expect(list, isEmpty);
  });

  test('watchFeaturesForAssignment only returns matching assignment',
      () async {
    final now = DateTime.now();
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f1',
            assignmentId: 'a1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: now,
          ),
        );
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f2',
            assignmentId: 'a2',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: now,
          ),
        );

    final list = await repo.watchFeaturesForAssignment('a1').first;
    expect(list, hasLength(1));
    expect(list.first.id, 'f1');
  });

  test('getFeature returns null for unknown id', () async {
    final f = await repo.getFeature('nope');
    expect(f, isNull);
  });

  group('markFeatureStatus', () {
    test('feature with no submissions stays unfilled', () async {
      await db.into(db.features).insert(
            FeaturesCompanion.insert(
              id: 'f1',
              assignmentId: 'a1',
              featureType: 'building',
              geometryGeojson: '{}',
              createdAt: DateTime.now(),
            ),
          );
      await repo.markFeatureStatus('f1');
      final f = (await db.select(db.features).get()).single;
      expect(f.status, 'unfilled');
    });

    test('feature with a draft + building_attributes is in_progress',
        () async {
      final now = DateTime.now();
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
      await db.into(db.buildingAttributes).insert(
            BuildingAttributesCompanion.insert(
              submissionId: 's1',
              buildingName: const Value('Hall'),
            ),
          );
      await repo.markFeatureStatus('f1');
      final f = (await db.select(db.features).get()).single;
      expect(f.status, 'in_progress');
    });

    test('feature with a ready_to_upload submission is complete', () async {
      final now = DateTime.now();
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
              syncStatus: const Value('ready_to_upload'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await repo.markFeatureStatus('f1');
      final f = (await db.select(db.features).get()).single;
      expect(f.status, 'complete');
    });

    test('does_not_exist submission without attrs is in_progress', () async {
      final now = DateTime.now();
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
              doesNotExist: const Value(true),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await repo.markFeatureStatus('f1');
      final f = (await db.select(db.features).get()).single;
      expect(f.status, 'in_progress');
    });
  });
}
