import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/remote_attributions_cache_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late RemoteAttributionsCacheRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = RemoteAttributionsCacheRepository(db);
  });

  tearDown(() => db.close());

  // ----- helpers -----------------------------------------------------------

  Map<String, dynamic> attributionRow({
    required String id,
    required String featureId,
    String? supersededAt,
    String? supersededById,
    String updatedAt = '2026-05-18T10:00:00Z',
    Map<String, dynamic>? attributeValues,
  }) => {
        'id': id,
        '__assignment_id': 'a1',
        'feature_id': featureId,
        'feature_type': 'building',
        'submitted_by': 'alice',
        'submitted_at': '2026-05-18T09:00:00Z',
        'superseded_at': supersededAt,
        'superseded_by_id': supersededById,
        'updated_at': updatedAt,
        'attribute_values': attributeValues ?? {'building': {'storeys': 2}},
      };

  Map<String, dynamic> newFeatureRow({
    required String id,
    String updatedAt = '2026-05-18T10:00:00Z',
  }) => {
        'id': id,
        'assignment_id': 'a1',
        'feature_type': 'building',
        'geometry_geojson':
            '{"type":"Point","coordinates":[121.0,14.5]}',
        'centroid_lat': 14.5,
        'centroid_lng': 121.0,
        'submitted_by': 'bob',
        'submitted_at': '2026-05-18T09:00:00Z',
        'possible_duplicate_of': null,
        'dedup_reviewed_at': null,
        'superseded_at': null,
        'superseded_by_id': null,
        'updated_at': updatedAt,
      };

  // ----- attributions ------------------------------------------------------

  test('upsertAttribution inserts a new row', () async {
    await repo.upsertAttribution(attributionRow(id: 's1', featureId: 'f1'));

    final rows = await repo.liveAttributionsFor('a1');
    expect(rows, hasLength(1));
    expect(rows.first.id, 's1');
    expect(rows.first.featureId, 'f1');
    expect(rows.first.supersededAt, isNull);
    expect(
      jsonDecode(rows.first.attributeValuesJson),
      {'building': {'storeys': 2}},
    );
  });

  test('upsertAttribution overwrites on conflict', () async {
    await repo.upsertAttribution(attributionRow(id: 's1', featureId: 'f1'));
    await repo.upsertAttribution(
      attributionRow(
        id: 's1',
        featureId: 'f1',
        supersededAt: '2026-05-18T11:00:00Z',
        supersededById: 's2',
        updatedAt: '2026-05-18T11:00:00Z',
      ),
    );

    final live = await repo.liveAttributionsFor('a1');
    expect(live, isEmpty,
        reason: 'supersede transition should remove row from live set');

    final all = await repo.attributionsForFeature('f1');
    expect(all, hasLength(1));
    expect(all.first.supersededAt, isNotNull);
    expect(all.first.supersededById, 's2');
  });

  test('upsertAttributionsBatch handles empty list gracefully', () async {
    await repo.upsertAttributionsBatch(const []);
    expect(await repo.liveAttributionsFor('a1'), isEmpty);
  });

  test('upsertAttribution throws if assignment_id is absent', () async {
    final row = attributionRow(id: 's1', featureId: 'f1')
      ..remove('__assignment_id');
    expect(() => repo.upsertAttribution(row), throwsStateError);
  });

  test('liveAttributionsFor only returns non-superseded rows', () async {
    await repo.upsertAttribution(attributionRow(id: 's1', featureId: 'f1'));
    await repo.upsertAttribution(
      attributionRow(
        id: 's2',
        featureId: 'f1',
        supersededAt: '2026-05-18T11:00:00Z',
      ),
    );

    final live = await repo.liveAttributionsFor('a1');
    expect(live.map((r) => r.id), ['s1']);
  });

  // ----- new features ------------------------------------------------------

  test('upsertNewFeature inserts a row with centroid', () async {
    await repo.upsertNewFeature(newFeatureRow(id: 'f1'));

    final rows = await repo.liveNewFeaturesFor('a1');
    expect(rows, hasLength(1));
    expect(rows.first.centroidLat, 14.5);
    expect(rows.first.centroidLng, 121.0);
    expect(rows.first.geometryGeojson, contains('Point'));
  });

  // ----- cursors -----------------------------------------------------------

  test('cursor setters initialize and update independently', () async {
    expect(await repo.getCursor('a1'), isNull);

    final c1 = DateTime.utc(2026, 5, 18, 10);
    await repo.setAttributionsCursor('a1', c1);
    var cur = await repo.getCursor('a1');
    expect(cur, isNotNull);
    // Drift stores DateTime as epoch seconds — compare moments, not fields,
    // since round-trip loses the UTC tag.
    expect(cur!.attributionsLastSyncAt!.isAtSameMomentAs(c1), isTrue);
    expect(cur.newFeaturesLastSyncAt, isNull);

    final c2 = DateTime.utc(2026, 5, 18, 11);
    await repo.setNewFeaturesCursor('a1', c2);
    cur = await repo.getCursor('a1');
    expect(cur!.attributionsLastSyncAt!.isAtSameMomentAs(c1), isTrue,
        reason: 'separate cursor field must not be clobbered');
    expect(cur.newFeaturesLastSyncAt!.isAtSameMomentAs(c2), isTrue);
  });

  test('clearAssignment removes cache + cursors for one assignment only',
      () async {
    await repo.upsertAttribution(attributionRow(id: 's1', featureId: 'f1'));
    await repo.upsertNewFeature(newFeatureRow(id: 'f1'));
    await repo.setAttributionsCursor('a1', DateTime.utc(2026, 5, 18));

    // Insert a row for a different assignment that must survive the clear.
    final otherRow = attributionRow(id: 's9', featureId: 'f9')
      ..['__assignment_id'] = 'a2';
    await repo.upsertAttribution(otherRow);

    await repo.clearAssignment('a1');

    expect(await repo.liveAttributionsFor('a1'), isEmpty);
    expect(await repo.liveNewFeaturesFor('a1'), isEmpty);
    expect(await repo.getCursor('a1'), isNull);
    expect(await repo.liveAttributionsFor('a2'), hasLength(1));
  });
}
