// ignore: unused_import
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/survey/olp_survey/data/household_survey_repository.dart';
import 'package:firecheck/features/survey/olp_survey/domain/construction_details.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_form_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late HouseholdSurveyRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = HouseholdSurveyRepository(db);
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

  tearDown(() async => db.close());

  test('upsert round-trips a fully populated state', () async {
    final state = OlpFormState(
      submissionId: 's1',
      checkedCodes: const {'B-01', 'C-10', 'D-25', 'E-30'},
      constructionDetails: const {
        'roof': ConstructionDetail(material: 'kahoy'),
        'mainDoor': ConstructionDetail(material: 'others', materialOther: 'aluminum'),
      },
      homeownerAcknowledged: true,
      completedAt: DateTime(2026, 4, 26, 12),
    );
    await repo.upsertForSubmission(
      state: state,
      lebelNgKahinaan: 'LabisNaMapanganib',
      safetySuggestionKeys: const ['olpItemB02Suggestion', 'olpItemC11Suggestion'],
    );

    final loaded = await repo.loadForSubmission('s1');
    expect(loaded, isNotNull);
    expect(loaded!.checkedCodes, {'B-01', 'C-10', 'D-25', 'E-30'});
    expect(loaded.constructionDetails['roof']?.material, 'kahoy');
    expect(loaded.constructionDetails['mainDoor']?.material, 'others');
    expect(loaded.constructionDetails['mainDoor']?.materialOther, 'aluminum');
    expect(loaded.homeownerAcknowledged, isTrue);
    expect(loaded.completedAt, DateTime(2026, 4, 26, 12));
  });

  test('upsert overwrites existing row', () async {
    await repo.upsertForSubmission(
      state: const OlpFormState(submissionId: 's1', checkedCodes: {'B-01'}),
      lebelNgKahinaan: 'LabisNaMapanganib',
      safetySuggestionKeys: const [],
    );
    await repo.upsertForSubmission(
      state: const OlpFormState(
        submissionId: 's1',
        checkedCodes: {'B-01', 'B-02'},
        homeownerAcknowledged: true,
      ),
      lebelNgKahinaan: 'LabisNaMapanganib',
      safetySuggestionKeys: const [],
    );
    final loaded = await repo.loadForSubmission('s1');
    expect(loaded!.checkedCodes, {'B-01', 'B-02'});
    expect(loaded.homeownerAcknowledged, isTrue);
  });

  test('loadForSubmission returns null when no row exists', () async {
    final loaded = await repo.loadForSubmission('s1');
    expect(loaded, isNull);
  });

  test('decodeCheckedCodes handles empty + many', () {
    expect(HouseholdSurveyRepository.decodeCheckedCodes('{}'), isEmpty);
    expect(
      HouseholdSurveyRepository.decodeCheckedCodes('{"B-01":true,"B-02":true}'),
      {'B-01', 'B-02'},
    );
  });

  test('decodeConstructionDetails handles empty + populated', () {
    expect(
      HouseholdSurveyRepository.decodeConstructionDetails('{}'),
      isEmpty,
    );
    final m = HouseholdSurveyRepository.decodeConstructionDetails(
      '{"roof":{"material":"kahoy"},"mainDoor":{"material":"others","materialOther":"glass"}}',
    );
    expect(m['roof']?.material, 'kahoy');
    expect(m['mainDoor']?.materialOther, 'glass');
  });
}
