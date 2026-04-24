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
}
