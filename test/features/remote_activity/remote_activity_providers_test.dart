import 'package:drift/native.dart';
import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/remote_attributions_cache_repository.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/remote_activity/presentation/remote_activity_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({
  required String id,
  required String featureId,
  required String submittedBy,
}) => {
      'id': id,
      '__assignment_id': 'a1',
      'feature_id': featureId,
      'feature_type': 'building',
      'submitted_by': submittedBy,
      'submitted_at': '2026-05-18T09:00:00Z',
      'superseded_at': null,
      'superseded_by_id': null,
      'updated_at': '2026-05-18T10:00:00Z',
      'attribute_values': {
        'building': {'storeys': 2},
      },
    };

void main() {
  late AppDatabase db;
  late RemoteAttributionsCacheRepository cache;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    cache = RemoteAttributionsCacheRepository(db);
    await db.into(db.assignments).insert(
          AssignmentsCompanion.insert(
            id: 'a1',
            enumeratorId: 'me',
            campaignId: 'c1',
            boundaryPolygonGeojson: '{}',
            createdAt: DateTime(2026, 5, 18),
          ),
        );
  });

  tearDown(() => db.close());

  ProviderContainer makeContainer({String? userId = 'me'}) {
    return ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        currentUserIdProvider.overrideWithValue(userId),
        assignmentRepositoryProvider
            .overrideWithValue(AssignmentRepository(db: db)),
      ],
    );
  }

  test('othersRemoteAttributionsProvider excludes my own submissions',
      () async {
    await cache
        .upsertAttribution(_row(id: 's1', featureId: 'f1', submittedBy: 'me'));
    await cache.upsertAttribution(
      _row(id: 's2', featureId: 'f2', submittedBy: 'alice'),
    );

    final container = makeContainer();
    addTearDown(container.dispose);

    // Make sure currentAssignmentProvider has resolved before reading the
    // dependent provider — its initial AsyncLoading emission would yield
    // an empty stream from othersRemoteAttributionsProvider.
    await container.read(currentAssignmentProvider.future);
    final views =
        await container.read(othersRemoteAttributionsProvider.future);
    expect(views.map((v) => v.id), ['s2']);
  });

  test('remoteActivityCountProvider de-duplicates by feature', () async {
    await cache.upsertAttribution(
      _row(id: 's1', featureId: 'f1', submittedBy: 'alice'),
    );
    await cache.upsertAttribution(
      _row(id: 's2', featureId: 'f1', submittedBy: 'bob'),
    );
    await cache.upsertAttribution(
      _row(id: 's3', featureId: 'f2', submittedBy: 'alice'),
    );

    final container = makeContainer();
    addTearDown(container.dispose);

    // Drain the stream once so .read on the count provider sees data.
    await container.read(currentAssignmentProvider.future);
    await container.read(othersRemoteAttributionsProvider.future);
    expect(container.read(remoteActivityCountProvider), 2);
  });

  test('when signed-out, all non-null submitted_by rows still surface',
      () async {
    // Spec: cache is "Clearable on logout" but if we're between sessions
    // and rows still exist locally, we don't crash — we just show
    // everything (the chip / list will appear, sign-in flow will overwrite).
    await cache.upsertAttribution(
      _row(id: 's1', featureId: 'f1', submittedBy: 'alice'),
    );

    final container = makeContainer(userId: null);
    addTearDown(container.dispose);

    // Make sure currentAssignmentProvider has resolved before reading the
    // dependent provider — its initial AsyncLoading emission would yield
    // an empty stream from othersRemoteAttributionsProvider.
    await container.read(currentAssignmentProvider.future);
    final views =
        await container.read(othersRemoteAttributionsProvider.future);
    expect(views, hasLength(1));
  });
}
