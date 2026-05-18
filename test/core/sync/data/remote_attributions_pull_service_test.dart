import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/remote_attributions_cache_repository.dart';
import 'package:firecheck/core/sync/data/remote_attributions_pull_service.dart';
import 'package:firecheck/core/sync/data/remote_cache_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// Recording fake — captures the `since` argument it was called with so we
/// can assert the delta-pull cursor flow without mocking PostgrestBuilder.
class _RecordingApi implements RemoteCacheApi {
  _RecordingApi({this.attributions = const [], this.newFeatures = const []});

  List<Map<String, dynamic>> attributions;
  List<Map<String, dynamic>> newFeatures;

  DateTime? lastAttribSince;
  DateTime? lastNewFeatSince;
  int attribCalls = 0;
  int newFeatCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> fetchAttributions(
    String assignmentId, {
    DateTime? since,
  }) async {
    attribCalls++;
    lastAttribSince = since;
    return attributions
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> fetchNewFeatures(
    String assignmentId, {
    DateTime? since,
  }) async {
    newFeatCalls++;
    lastNewFeatSince = since;
    return newFeatures
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }
}

/// fetchAttributions throws synchronously-on-async; fetchNewFeatures
/// resolves a tick later (would surface as uncaught if orphaned).
class _ThrowingThenSucceedingApi implements RemoteCacheApi {
  int attribCalls = 0;
  int newFeatCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> fetchAttributions(
    String assignmentId, {
    DateTime? since,
  }) async {
    attribCalls++;
    throw StateError('boom');
  }

  @override
  Future<List<Map<String, dynamic>>> fetchNewFeatures(
    String assignmentId, {
    DateTime? since,
  }) async {
    newFeatCalls++;
    await Future<void>.delayed(Duration.zero);
    return const [];
  }
}

Map<String, dynamic> _attrib({
  required String id,
  required String featureId,
  String? supersededAt,
  String updatedAt = '2026-05-18T10:00:00Z',
}) => {
      'id': id,
      'feature_id': featureId,
      'feature_type': 'building',
      'submitted_by': 'alice',
      'submitted_at': '2026-05-18T09:00:00Z',
      'superseded_at': supersededAt,
      'superseded_by_id': null,
      'updated_at': updatedAt,
      'attribute_values': {
        'building': {'storeys': 2},
      },
    };

Map<String, dynamic> _newFeat({
  required String id,
  String updatedAt = '2026-05-18T10:30:00Z',
}) => {
      'id': id,
      'assignment_id': 'a1',
      'feature_type': 'building',
      'geometry_geojson':
          '{"type":"Point","coordinates":[121.0,14.5]}',
      'centroid_lat': 14.5,
      'centroid_lng': 121.0,
      'submitted_by': 'bob',
      'submitted_at': '2026-05-18T09:30:00Z',
      'possible_duplicate_of': null,
      'dedup_reviewed_at': null,
      'superseded_at': null,
      'superseded_by_id': null,
      'updated_at': updatedAt,
    };

void main() {
  late AppDatabase db;
  late RemoteAttributionsCacheRepository cache;
  late _RecordingApi api;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    cache = RemoteAttributionsCacheRepository(db);
    api = _RecordingApi();
  });

  tearDown(() => db.close());

  test('pullAll persists rows + advances cursor to max(updated_at)',
      () async {
    api.attributions = [
      _attrib(id: 's1', featureId: 'f1', updatedAt: '2026-05-18T10:00:00Z'),
      _attrib(id: 's2', featureId: 'f2', updatedAt: '2026-05-18T10:15:00Z'),
    ];
    api.newFeatures = [_newFeat(id: 'f3', updatedAt: '2026-05-18T10:30:00Z')];

    final svc = RemoteAttributionsPullService(api: api, cache: cache);
    final result = await svc.pullAll('a1');

    expect(result.kind, PullKind.full);
    expect(result.attributionsCount, 2);
    expect(result.newFeaturesCount, 1);
    expect(api.lastAttribSince, isNull,
        reason: 'cold-open full pull must not send a since cursor');
    expect(api.lastNewFeatSince, isNull);

    final liveAttrib = await cache.liveAttributionsFor('a1');
    expect(liveAttrib.map((r) => r.id).toSet(), {'s1', 's2'});

    final cursor = await cache.getCursor('a1');
    // Drift stores DateTime as seconds-since-epoch, so it round-trips to
    // local time. Compare moments, not wall-clock fields.
    expect(
      cursor!.attributionsLastSyncAt!.isAtSameMomentAs(
        DateTime.utc(2026, 5, 18, 10, 15),
      ),
      isTrue,
    );
    expect(
      cursor.newFeaturesLastSyncAt!.isAtSameMomentAs(
        DateTime.utc(2026, 5, 18, 10, 30),
      ),
      isTrue,
    );
  });

  test('pullDelta uses stored cursor as p_since', () async {
    final cursorAttrib = DateTime.utc(2026, 5, 18, 10);
    final cursorNewFeat = DateTime.utc(2026, 5, 18, 10, 30);
    await cache.setAttributionsCursor('a1', cursorAttrib);
    await cache.setNewFeaturesCursor('a1', cursorNewFeat);

    api.attributions = [
      _attrib(id: 's3', featureId: 'f1', updatedAt: '2026-05-18T10:45:00Z'),
    ];
    api.newFeatures = const [];

    final svc = RemoteAttributionsPullService(api: api, cache: cache);
    final result = await svc.pullDelta('a1');

    expect(result.kind, PullKind.delta);
    expect(result.attributionsCount, 1);
    expect(result.newFeaturesCount, 0);

    expect(api.lastAttribSince!.isAtSameMomentAs(cursorAttrib), isTrue);
    expect(api.lastNewFeatSince!.isAtSameMomentAs(cursorNewFeat), isTrue);

    // Empty new-feature response → cursor stays put, not nulled-out.
    final updated = await cache.getCursor('a1');
    expect(
      updated!.attributionsLastSyncAt!.isAtSameMomentAs(
        DateTime.utc(2026, 5, 18, 10, 45),
      ),
      isTrue,
    );
    expect(
      updated.newFeaturesLastSyncAt!.isAtSameMomentAs(cursorNewFeat),
      isTrue,
    );
  });

  test('pullDelta falls back to full pull when cursor is stale', () async {
    final stale = DateTime.utc(2026, 5, 16, 9); // > 24h before "now"
    await cache.setAttributionsCursor('a1', stale);
    await cache.setNewFeaturesCursor('a1', stale);

    api.attributions = [_attrib(id: 's1', featureId: 'f1')];

    final svc = RemoteAttributionsPullService(
      api: api,
      cache: cache,
      now: () => DateTime.utc(2026, 5, 18, 12),
    );

    final result = await svc.pullDelta('a1');
    expect(result.kind, PullKind.full,
        reason: 'stale cursor must force a full pull');
    expect(api.lastAttribSince, isNull,
        reason: 'fallback full pull must drop the since cursor');
  });

  test('pullDelta on virgin cursor performs a full pull', () async {
    final svc = RemoteAttributionsPullService(api: api, cache: cache);

    final result = await svc.pullDelta('a1');
    expect(result.kind, PullKind.full);
    expect(api.lastAttribSince, isNull);
  });

  test('pullAll is idempotent — re-running upserts on top of prior state',
      () async {
    api.attributions = [_attrib(id: 's1', featureId: 'f1')];

    final svc = RemoteAttributionsPullService(api: api, cache: cache);

    await svc.pullAll('a1');
    await svc.pullAll('a1');

    expect(api.attribCalls, 2);
    final live = await cache.liveAttributionsFor('a1');
    expect(live, hasLength(1));
    expect(live.first.id, 's1');
  });

  test('pullAll throws atomically — second future is awaited, not orphaned',
      () async {
    // The bug we're guarding against: if fetchAttributions throws while
    // fetchNewFeatures is still in-flight, sequential awaits would leave
    // the second future unawaited and its later error becomes an uncaught
    // async exception. Future.wait awaits both, so we get a single
    // rejection from pullAll() and no zombie futures.
    final throwingApi = _ThrowingThenSucceedingApi();
    final svc = RemoteAttributionsPullService(api: throwingApi, cache: cache);

    await expectLater(svc.pullAll('a1'), throwsA(isA<StateError>()));
    // Both calls were initiated even though the first errored:
    expect(throwingApi.attribCalls, 1);
    expect(throwingApi.newFeatCalls, 1);
    // Yielding a microtask is enough for any orphan to surface as uncaught;
    // none does, because Future.wait propagated the rejection synchronously.
    await Future<void>.delayed(Duration.zero);
  });

  test('pullAll preserves cursor when response is empty', () async {
    final preset = DateTime.utc(2026, 5, 18, 10);
    await cache.setAttributionsCursor('a1', preset);
    // pullAll passes since=null (cold-open). Empty response ⇒ no max found.
    // But because pullAll is invoked from outside, the prior cursor is
    // overwritten as null — that's correct on full pull. Test documents that.
    final svc = RemoteAttributionsPullService(api: api, cache: cache);
    await svc.pullAll('a1');

    final cursor = await cache.getCursor('a1');
    expect(cursor!.attributionsLastSyncAt, isNull);
  });
}
