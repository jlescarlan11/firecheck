import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/new_feature/data/new_feature_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late NewFeatureRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = NewFeatureRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('createFeature', () {
    test('inserts a row with the supplied GeoJSON, isNew=true', () async {
      // Seed an assignment so the FK is satisfied.
      await db.into(db.assignments).insert(
            AssignmentsCompanion.insert(
              id: 'a1',
              enumeratorId: 'admin',
              campaignId: 'c1',
              boundaryPolygonGeojson: '',
              createdAt: DateTime.now(),
            ),
          );

      const geom =
          '{"type":"Polygon","coordinates":[[[1,1],[2,1],[1.5,2],[1,1]]]}';
      final f = await repo.createFeature(
        assignmentId: 'a1',
        featureType: 'building',
        geometryGeojson: geom,
      );

      expect(f.assignmentId, 'a1');
      expect(f.featureType, 'building');
      expect(f.geometryGeojson, geom);
      expect(f.isNew, isTrue);
      expect(f.id, isNotEmpty);
    });

    test('different calls produce different IDs', () async {
      await db.into(db.assignments).insert(
            AssignmentsCompanion.insert(
              id: 'a1',
              enumeratorId: 'admin',
              campaignId: 'c1',
              boundaryPolygonGeojson: '',
              createdAt: DateTime.now(),
            ),
          );
      final f1 = await repo.createFeature(
        assignmentId: 'a1',
        featureType: 'point',
        geometryGeojson: '{"type":"Point","coordinates":[1,1]}',
      );
      final f2 = await repo.createFeature(
        assignmentId: 'a1',
        featureType: 'point',
        geometryGeojson: '{"type":"Point","coordinates":[2,2]}',
      );
      expect(f1.id, isNot(f2.id));
    });
  });
}
