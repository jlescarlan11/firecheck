import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/map/data/feature_repository.dart';
import 'package:firecheck/features/survey/building_form/data/building_attributes_repository.dart';
import 'package:firecheck/features/survey/building_form/data/submission_repository.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SubmissionRepository sr;
  late BuildingAttributesRepository ar;
  late FeatureRepository fr;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sr = SubmissionRepository(db);
    ar = BuildingAttributesRepository(db);
    fr = FeatureRepository(db);
    final now = DateTime.now();
    // Seed FK chain: features → assignments not needed (no FK declared in
    // Drift), but building_attributes → submissions → features is all
    // declared logically; in-memory SQLite without explicit FOREIGN KEY in
    // Drift schema still requires parents to exist for markFeatureStatus
    // to find rows.
    await db.into(db.features).insert(
          FeaturesCompanion.insert(
            id: 'f1',
            assignmentId: 'a1',
            featureType: 'building',
            geometryGeojson: '{}',
            createdAt: now,
          ),
        );
  });

  tearDown(() async => db.close());

  test('debounced write lands after 500ms', () async {
    final s = await sr.ensureDraftForFeature(
      featureId: 'f1',
      enumeratorId: 'u1',
    );
    BuildingFormNotifier(
      submissionId: s.id,
      featureId: 'f1',
      submissionRepo: sr,
      attrsRepo: ar,
      featureRepo: fr,
    ).update((st) => st.copyWith(buildingName: 'Hall'));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final attrs = await ar.watchForSubmission(s.id).first;
    expect(attrs, isNotNull);
    expect(attrs!.buildingName, 'Hall');
  });

  test('flushNow writes immediately', () async {
    final s = await sr.ensureDraftForFeature(
      featureId: 'f1',
      enumeratorId: 'u1',
    );
    final n = BuildingFormNotifier(
      submissionId: s.id,
      featureId: 'f1',
      submissionRepo: sr,
      attrsRepo: ar,
      featureRepo: fr,
    )..update((st) => st.copyWith(buildingName: 'Hall'));
    await n.flushNow();
    final attrs = await ar.watchForSubmission(s.id).first;
    expect(attrs!.buildingName, 'Hall');
  });

  test('does-not-exist toggle flips submissions row', () async {
    final s = await sr.ensureDraftForFeature(
      featureId: 'f1',
      enumeratorId: 'u1',
    );
    final n = BuildingFormNotifier(
      submissionId: s.id,
      featureId: 'f1',
      submissionRepo: sr,
      attrsRepo: ar,
      featureRepo: fr,
    )..update((st) => st.copyWith(doesNotExist: true));
    await n.flushNow();
    final reloaded = (await db.select(db.submissions).get()).single;
    expect(reloaded.doesNotExist, isTrue);
  });
}
