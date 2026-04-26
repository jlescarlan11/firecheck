import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/olp_survey/data/household_survey_repository.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section_providers.dart';
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

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('debounced write lands after 500ms', () async {
    const key = OlpFormKey(submissionId: 's1', featureId: 'f1');
    container.read(olpSectionNotifierProvider(key).notifier)
      ..toggleItem('B-01')
      ..toggleItem('C-10');

    await Future<void>.delayed(const Duration(milliseconds: 600));

    final repo = HouseholdSurveyRepository(db);
    final loaded = await repo.loadForSubmission('s1');
    expect(loaded, isNotNull);
    expect(loaded!.checkedCodes, {'B-01', 'C-10'});
  });

  test('flushNow writes immediately + persists computed lebel + suggestions',
      () async {
    const key = OlpFormKey(submissionId: 's1', featureId: 'f1');
    final notifier = container.read(olpSectionNotifierProvider(key).notifier)
      ..toggleItem('B-01');
    await notifier.flushNow();

    final row = await (db.select(db.householdSurveys)
          ..where((t) => t.submissionId.equals('s1')))
        .getSingle();
    expect(row.lebelNgKahinaan, 'LabisNaMapanganib');
    expect(row.safetySuggestions, contains('olpItemB02Suggestion'));
  });

  test('setHomeownerAcknowledged toggles + persists', () async {
    const key = OlpFormKey(submissionId: 's1', featureId: 'f1');
    final notifier = container.read(olpSectionNotifierProvider(key).notifier)
      ..setHomeownerAcknowledged(acknowledged: true);
    await notifier.flushNow();

    final row = await (db.select(db.householdSurveys)
          ..where((t) => t.submissionId.equals('s1')))
        .getSingle();
    expect(row.homeownerAcknowledged, isTrue);
  });

  test('markComplete sets completedAt and flushes', () async {
    const key = OlpFormKey(submissionId: 's1', featureId: 'f1');
    final notifier = container.read(olpSectionNotifierProvider(key).notifier);
    await notifier.markComplete();

    final row = await (db.select(db.householdSurveys)
          ..where((t) => t.submissionId.equals('s1')))
        .getSingle();
    expect(row.completedAt, isNotNull);
  });
}
