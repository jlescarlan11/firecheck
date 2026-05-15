import 'dart:convert';

import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/new_feature/data/new_feature_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late NewFeatureRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = NewFeatureRepository(db);
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'admin',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: DateTime.now(),
          ),
        );
  });

  tearDown(() async => db.close());

  test('createNewFeature inserts a Point feature with isNew=true', () async {
    final f = await repo.createNewFeature(
      assignmentId: 'a1',
      featureType: 'building',
      lat: 10.31810,
      lng: 123.88270,
    );

    expect(f.assignmentId, 'a1');
    expect(f.featureType, 'building');
    expect(f.isNew, isTrue);
    expect(f.status, 'unfilled');

    final geom = jsonDecode(f.geometryGeojson) as Map<String, dynamic>;
    expect(geom['type'], 'Point');
    final coords = geom['coordinates'] as List;
    expect((coords[0] as num).toDouble(), closeTo(123.88270, 1e-6));
    expect((coords[1] as num).toDouble(), closeTo(10.31810, 1e-6));
  });

  test('road type also accepted', () async {
    final f = await repo.createNewFeature(
      assignmentId: 'a1',
      featureType: 'road',
      lat: 10.31810,
      lng: 123.88270,
    );
    expect(f.featureType, 'road');
    expect(f.isNew, isTrue);
  });

  test('returns rows with unique ids on consecutive calls', () async {
    final a = await repo.createNewFeature(
      assignmentId: 'a1',
      featureType: 'building',
      lat: 10,
      lng: 123,
    );
    final b = await repo.createNewFeature(
      assignmentId: 'a1',
      featureType: 'building',
      lat: 10,
      lng: 123,
    );
    expect(a.id, isNot(equals(b.id)));
  });

  group('createFeature', () {
    test('inserts a row with the supplied GeoJSON, isNew=true', () async {
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
