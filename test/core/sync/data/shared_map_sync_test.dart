import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/shared_map_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SharedMapSync sync;
  Map<String, dynamic> feature(String id, {bool deleted = false}) => {
        'id': id,
        'assignment_id': 'map',
        'feature_type': 'building',
        'geometry_geojson': {
          'type': 'Point',
          'coordinates': [1, 2]
        },
        'created_at': '2026-09-16T00:00:00Z',
        'deleted': deleted,
        'submissions': [],
      };
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sync = SharedMapSync(
        db: db,
        accountId: 'user',
        fetch: (id, a, t) async => {'enabled': false});
  });
  tearDown(() async {
    await db.close();
  });
  test(
      'bundle atomically applies all features and cursor; malformed row rolls back',
      () async {
    await sync.applyBundle('map', 1, [feature('one'), feature('two')]);
    expect((await db.select(db.features).get()).length, 2);
    await expectLater(
        sync.applyBundle('map', 2, [
          feature('three'),
          {'id': 'bad', 'assignment_id': 'other'}
        ]),
        throwsStateError);
    expect((await db.select(db.sharedMapCursors).getSingle()).revision, 1);
    expect((await db.select(db.features).get()).length, 2);
    await sync.applyBundle('map', 1, [feature('one', deleted: true)]);
    expect((await db.select(db.features).get()).length, 2);
  });
  Map<String, dynamic> observation({
    String assignment = 'map',
    String featureId = 'one',
  }) =>
      {
        'id': 'accepted',
        'assignment_id': assignment,
        'feature_id': featureId,
        'feature_type': 'building',
        'attribute_values': {'storeys': 2},
        'submitted_at': '2026-09-16T00:00:00Z',
        'updated_at': '2026-09-16T00:00:00Z',
      };

  for (final mismatch in ['assignment', 'feature', 'synthetic']) {
    test('nested $mismatch mismatch rolls back mirror deletion and cursor',
        () async {
      final original = feature('one')..['submissions'] = [observation()];
      await sync.applyBundle('map', 1, [original]);
      final bad = observation(
        assignment: mismatch == 'assignment' ? 'other' : 'map',
        featureId: mismatch == 'feature' ? 'other' : 'one',
      );
      if (mismatch == 'synthetic') bad['__assignment_id'] = 'other';
      await expectLater(
        sync.applyBundle('map', 2, [
          feature('two'),
          feature('one')..['submissions'] = [bad],
        ]),
        throwsStateError,
      );
      expect((await db.select(db.sharedMapCursors).getSingle()).revision, 1);
      expect(
        (await db.select(db.remoteAttributionsCache).getSingle()).assignmentId,
        'map',
      );
      expect(
        (await db.select(db.remoteAttributionsCache).getSingle()).featureId,
        'one',
      );
      expect((await db.select(db.features).get()).map((f) => f.id), ['one']);
      expect(
        jsonDecode(
          (await db.select(db.sharedMapFeatures).getSingle()).payloadJson,
        ),
        original,
      );
    });
  }

  test('tombstone cannot bypass nested observation identity validation',
      () async {
    await sync.applyBundle('map', 1, [
      feature('one')..['submissions'] = [observation()],
    ]);
    await expectLater(
      sync.applyBundle('map', 2, [
        feature('one', deleted: true)
          ..['submissions'] = [observation(assignment: 'other')],
      ]),
      throwsStateError,
    );
    expect((await db.select(db.sharedMapCursors).getSingle()).revision, 1);
    expect(
      (await db.select(db.remoteAttributionsCache).getSingle()).assignmentId,
      'map',
    );
    expect((await db.select(db.features).getSingle()).mergedIntoId, isNull);
  });

  test('nested context supplies absent assignment and feature aliases',
      () async {
    final nested = observation()
      ..remove('assignment_id')
      ..remove('feature_id');
    await sync.applyBundle('map', 1, [
      feature('one')..['submissions'] = [nested],
    ]);
    final accepted = await db.select(db.remoteAttributionsCache).getSingle();
    expect(accepted.assignmentId, 'map');
    expect(accepted.featureId, 'one');
  });

  for (final pending in ['draft', 'geometry']) {
    for (final transport in ['bundle', 'snapshot']) {
      test(
          '$transport rejects a foreign feature with pending $pending before projection',
          () async {
        await sync.applyBundle(
          'other',
          1,
          [feature('one')..['assignment_id'] = 'other'],
        );
        if (pending == 'draft') {
          await db.into(db.submissions).insert(
                SubmissionsCompanion.insert(
                  id: 'draft',
                  featureId: 'one',
                  createdAt: DateTime(2026),
                  updatedAt: DateTime(2026),
                ),
              );
        } else {
          await db.into(db.featureGeometryRevisions).insert(
                FeatureGeometryRevisionsCompanion.insert(
                  id: 'geometry',
                  featureId: 'one',
                  prevGeojson: '{}',
                  newGeojson: '{}',
                  editedBy: 'user',
                  editedAt: DateTime(2026),
                  createdAt: DateTime(2026),
                ),
              );
        }
        final incoming = feature('one')..['submissions'] = [observation()];
        final operation = transport == 'bundle'
            ? sync.applyBundle('map', 1, [incoming])
            : sync.installSnapshot({
                'schema_version': 1,
                'assignment_id': 'map',
                'revision': 10,
                'assignment': {
                  'id': 'map',
                  'campaign_id': 'campaign',
                  'name': 'Map',
                  'boundary': <String, dynamic>{}
                },
                'features': [incoming],
              });
        await expectLater(operation, throwsStateError);
        expect(
          (await db.select(db.features).getSingle()).assignmentId,
          'other',
        );
        expect(await db.select(db.remoteAttributionsCache).get(), isEmpty);
        expect(
          (await db.select(db.sharedMapCursors).getSingle()).assignmentId,
          'other',
        );
        expect(
          (await db.select(db.sharedMapFeatures).getSingle()).assignmentId,
          'other',
        );
        expect(
          (await db.select(db.submissions).get()).length,
          pending == 'draft' ? 1 : 0,
        );
        expect(
          (await db.select(db.featureGeometryRevisions).get()).length,
          pending == 'geometry' ? 1 : 0,
        );
      });
    }
  }

  test('remote geometry and deletion preserve dirty drafts and retain new base',
      () async {
    await sync.applyBundle('map', 1, [feature('one')]);
    await db.into(db.submissions).insert(SubmissionsCompanion.insert(
        id: 'draft',
        featureId: 'one',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now()));
    await sync.applyBundle('map', 2, [feature('one', deleted: true)]);
    expect((await db.select(db.features).getSingle()).mergedIntoId, isNull);
    expect((await db.select(db.submissions).getSingle()).syncStatus, 'draft');
    expect(
        jsonDecode((await db.select(db.sharedMapFeatures).getSingle())
            .payloadJson)['deleted'],
        true);
  });
  test('deferred server state is projected once the local draft is resolved',
      () async {
    await sync.applyBundle('map', 1, [feature('one')]);
    await db.into(db.submissions).insert(SubmissionsCompanion.insert(
        id: 'draft',
        featureId: 'one',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now()));
    await sync.applyBundle('map', 2, [feature('one', deleted: true)]);
    await (db.update(db.submissions)..where((t) => t.id.equals('draft')))
        .write(const SubmissionsCompanion(syncStatus: Value('withdrawn')));
    await sync.reconcile('map');
    expect((await db.select(db.features).getSingle()).mergedIntoId, 'one');
    expect(
        (await db.select(db.sharedMapFeatures).getSingle()).pendingProjection,
        false);
  });

  test('discarded geometry allows deferred server changes to reconcile',
      () async {
    await sync.applyBundle('map', 1, [feature('one')]);
    await db.into(db.featureGeometryRevisions).insert(
        FeatureGeometryRevisionsCompanion.insert(
            id: 'revision',
            featureId: 'one',
            prevGeojson: '{}',
            newGeojson: '{}',
            editedBy: 'user',
            editedAt: DateTime(2026),
            createdAt: DateTime(2026),
            syncStatus: const Value('failed')));
    await sync.applyBundle('map', 2, [feature('one', deleted: true)]);
    expect((await db.select(db.features).getSingle()).mergedIntoId, isNull);
    await (db.update(db.featureGeometryRevisions)
          ..where((r) => r.id.equals('revision')))
        .write(const FeatureGeometryRevisionsCompanion(
            syncStatus: Value('discarded')));
    await sync.reconcile('map');
    expect((await db.select(db.features).getSingle()).mergedIntoId, 'one');
    expect(
        (await db.select(db.sharedMapFeatures).getSingle()).pendingProjection,
        false);
  });

  test('tombstone hides clean feature and removes its accepted observations',
      () async {
    await sync.applyBundle('map', 1, [feature('one')]);
    await sync.applyBundle('map', 2, [feature('one', deleted: true)]);
    expect((await db.select(db.features).getSingle()).mergedIntoId, 'one');
  });
  test(
      'pull pins high-water, detects gap and resumes after last committed bundle',
      () async {
    final calls = <int>[];
    final pull = SharedMapSync(
        db: db,
        accountId: 'user',
        fetch: (id, a, t) async {
          calls.add(a);
          if (a == 0)
            return {
              'enabled': true,
              'through_revision': 2,
              'next_revision': 1,
              'has_more': true,
              'bundles': [
                {
                  'revision': 1,
                  'features': [feature('one')]
                }
              ]
            };
          expect(t, 2);
          return {
            'enabled': true,
            'through_revision': 2,
            'next_revision': 2,
            'has_more': false,
            'bundles': [
              {
                'revision': 2,
                'features': [feature('two')]
              }
            ]
          };
        });
    expect(await pull.pull('map'), true);
    expect(calls, [0, 1]);
    expect((await db.select(db.sharedMapCursors).getSingle()).revision, 2);
  });
  test(
      'snapshot preserves local draft and installs exact revision without mobile publishing',
      () async {
    await sync.installSnapshot({
      'schema_version': 1,
      'assignment_id': 'map',
      'revision': 10,
      'assignment': {
        'id': 'map',
        'campaign_id': 'campaign',
        'name': 'Map',
        'boundary': {},
      },
      'features': [feature('one')]
    });
    expect((await db.select(db.sharedMapCursors).getSingle()).revision, 10);
    await expectLater(
        sync.applyBundle('map', 12, [feature('two')]), throwsStateError);
    await sync.applyBundle('map', 11, [feature('two')]);
    expect((await db.select(db.features).get()).length, 2);
  });
}
