import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/road_form/data/road_attributes_repository.dart';
import 'package:firecheck/features/survey/road_form/presentation/road_form_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
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

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('debounced write lands in road_attributes after 500ms', () async {
    const key = RoadFormKey(submissionId: 's1', featureId: 'f1');
    container.read(roadFormNotifierProvider(key).notifier)
      ..update((s) => s.copyWith(roadName: 'Mango Ave'))
      ..update((s) => s.copyWith(widthMeters: 4.5));

    await Future<void>.delayed(const Duration(milliseconds: 600));

    final repo = RoadAttributesRepository(db);
    final found = await repo.findBySubmission('s1');
    expect(found, isNotNull);
    expect(found!.roadName, 'Mango Ave');
    expect(found.widthMeters, 4.5);
  });

  test('flushNow writes immediately', () async {
    const key = RoadFormKey(submissionId: 's1', featureId: 'f1');
    final notifier = container.read(roadFormNotifierProvider(key).notifier);
    await (notifier..update((s) => s.copyWith(widthMeters: 6))).flushNow();

    final repo = RoadAttributesRepository(db);
    final found = await repo.findBySubmission('s1');
    expect(found!.widthMeters, 6);
  });

  test('does-not-exist toggle flips submissions row', () async {
    const key = RoadFormKey(submissionId: 's1', featureId: 'f1');
    final notifier = container.read(roadFormNotifierProvider(key).notifier);
    await (notifier..update((s) => s.copyWith(doesNotExist: true))).flushNow();

    final sub = await (db.select(db.submissions)
          ..where((t) => t.id.equals('s1')))
        .getSingle();
    expect(sub.doesNotExist, isTrue);
  });
}
