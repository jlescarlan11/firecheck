import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/data/submission_payload_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SubmissionPayloadBuilder builder;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    builder = SubmissionPayloadBuilder(db);
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

  test('building submission with no attrs or olp', () async {
    final p = await builder.build('s1');
    expect(p['submission'], isA<Map<String, dynamic>>());
    expect(p['feature_type'], 'building');
    expect(p['building_attributes'], isNull);
    expect(p['road_attributes'], isNull);
    expect(p['household_survey'], isNull);
  });

  test('building submission with attrs + olp', () async {
    await db.into(db.buildingAttributes).insert(
          BuildingAttributesCompanion.insert(
            submissionId: 's1',
            buildingName: const Value('Hall A'),
            ra9514Type: const Value('A'),
            storeys: const Value(2),
          ),
        );
    await db.into(db.householdSurveys).insert(
          HouseholdSurveysCompanion.insert(
            submissionId: 's1',
            kaayusanJson: const Value('{"B-01":true}'),
            homeownerAcknowledged: const Value(true),
            lebelNgKahinaan: const Value('LabisNaMapanganib'),
          ),
        );
    final p = await builder.build('s1');
    expect((p['building_attributes'] as Map)['building_name'], 'Hall A');
    expect((p['household_survey'] as Map)['homeowner_acknowledged'], true);
    expect((p['household_survey'] as Map)['lebel_ng_kahinaan'], 'LabisNaMapanganib');
  });

  test('road submission with road_attributes', () async {
    await (db.update(db.features)..where((t) => t.id.equals('f1')))
        .write(const FeaturesCompanion(featureType: Value('road')));
    await db.into(db.roadAttributes).insert(
          RoadAttributesCompanion.insert(
            submissionId: 's1',
            roadName: const Value('Mango Ave'),
            widthMeters: const Value(4.5),
          ),
        );
    final p = await builder.build('s1');
    expect(p['feature_type'], 'road');
    expect((p['road_attributes'] as Map)['road_name'], 'Mango Ave');
    expect((p['road_attributes'] as Map)['width_meters'], 4.5);
    expect(p['building_attributes'], isNull);
  });
}
