import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/map/data/feature_repository.dart';
import 'package:firecheck/features/survey/building_form/data/building_attributes_repository.dart';
import 'package:firecheck/features/survey/building_form/data/submission_repository.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

class _DelayedAttributes extends BuildingAttributesRepository {
  _DelayedAttributes(super.db);

  final loaded = Completer<BuildingAttribute?>();

  @override
  Stream<BuildingAttribute?> watchForSubmission(String submissionId) =>
      loaded.future.asStream();
}

class _FailingAttributes extends BuildingAttributesRepository {
  _FailingAttributes(super.db);

  bool fail = true;

  @override
  Future<void> upsertForSubmission({
    required String submissionId,
    String? cbmsId,
    String? buildingName,
    String? ra9514Type,
    int? storeys,
    String? material,
    bool costIsExact = false,
    double? costAmount,
    String? costEstimateRange,
    List<String> fireFightingFacilities = const [],
    List<String> fireLoad = const [],
  }) {
    if (fail) throw StateError('Storage unavailable');
    return super.upsertForSubmission(
      submissionId: submissionId,
      cbmsId: cbmsId,
      buildingName: buildingName,
      ra9514Type: ra9514Type,
      storeys: storeys,
      material: material,
      costIsExact: costIsExact,
      costAmount: costAmount,
      costEstimateRange: costEstimateRange,
      fireFightingFacilities: fireFightingFacilities,
      fireLoad: fireLoad,
    );
  }
}

void main() {
  late AppDatabase db;
  late BuildingAttributesRepository attributes;
  late SubmissionRepository submissions;
  final savedAt = DateTime.utc(2026);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    attributes = BuildingAttributesRepository(db);
    submissions = SubmissionRepository(db);
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
          id: 'map',
          enumeratorId: 'author',
          campaignId: 'map',
          boundaryPolygonGeojson: '{}',
          createdAt: savedAt,
        ),);
    await db.into(db.features).insert(FeaturesCompanion.insert(
          id: 'feature',
          assignmentId: 'map',
          featureType: 'building',
          geometryGeojson: '{}',
          createdAt: savedAt,
        ),);
    await db.into(db.submissions).insert(SubmissionsCompanion.insert(
          id: 'survey',
          featureId: 'feature',
          submittedBy: const Value('author'),
          syncStatus: const Value('uploaded'),
          createdAt: savedAt,
          updatedAt: savedAt,
        ),);
    await db.into(db.buildingAttributes).insert(
          BuildingAttributesCompanion.insert(
            submissionId: 'survey',
            buildingName: const Value('Saved building'),
            ra9514Type: const Value('C'),
            storeys: const Value(4),
            costIsExact: const Value(true),
            costAmount: const Value(100),
            fireFightingFacilitiesJson: const Value('["Hose"]'),
          ),
        );
  });
  tearDown(() async => db.close());

  BuildingFormNotifier notifier(BuildingAttributesRepository repo) =>
      BuildingFormNotifier(
        submissionId: 'survey',
        featureId: 'feature',
        attrsRepo: repo,
        submissionRepo: submissions,
        featureRepo: FeatureRepository(db),
      );

  test('no-op hydration preserves a saved does-not-exist flag and answers',
      () async {
    await (db.update(db.submissions)..where((s) => s.id.equals('survey')))
        .write(const SubmissionsCompanion(doesNotExist: Value(true)));
    final form = notifier(attributes);
    await form.flushNow();
    expect(form.state.doesNotExist, isTrue);
    expect(form.state.buildingName, 'Saved building');
    final saved = await submissions.findById('survey');
    expect(saved!.doesNotExist, isTrue);
    expect(saved.syncStatus, 'uploaded');
    expect(saved.updatedAt.toUtc(), savedAt);
    form.dispose();
  });

  test('an early edit hydrates untouched answers and applies a clear once',
      () async {
    final saved = await attributes.watchForSubmission('survey').first;
    final delayed = _DelayedAttributes(db);
    final form = notifier(delayed);
    var applications = 0;
    form.update((state) {
      applications++;
      return state.copyWith(
        buildingName: 'Changed before load',
        costIsExact: false,
        fireFightingFacilities: [],
      );
    });
    final flushing = form.flushNow();
    delayed.loaded.complete(saved);
    await flushing;
    final changed = await attributes.watchForSubmission('survey').first;
    expect(changed!.buildingName, 'Changed before load');
    expect(changed.storeys, 4);
    expect(changed.ra9514Type, 'C');
    expect(changed.costIsExact, isFalse);
    expect(changed.costAmount, isNull);
    expect(changed.fireFightingFacilitiesJson, '[]');
    expect(applications, 1);
    form.dispose();
  });

  test('an early false toggle overrides a durable true flag', () async {
    await (db.update(db.submissions)..where((s) => s.id.equals('survey')))
        .write(const SubmissionsCompanion(doesNotExist: Value(true)));
    final saved = await attributes.watchForSubmission('survey').first;
    final delayed = _DelayedAttributes(db);
    final form = notifier(delayed)
      ..update((state) => state.copyWith(doesNotExist: false));
    final flushing = form.flushNow();
    delayed.loaded.complete(saved);
    await flushing;
    expect((await submissions.findById('survey'))!.doesNotExist, isFalse);
    final changed = await attributes.watchForSubmission('survey').first;
    expect(changed!.buildingName, 'Saved building');
    expect(changed.storeys, 4);
    form.dispose();
  });

  test('disposing before hydration does not persist blank constructor values',
      () async {
    final saved = await attributes.watchForSubmission('survey').first;
    final delayed = _DelayedAttributes(db);
    final form = notifier(delayed);
    final flushing = form.flushNow();
    form.dispose();
    delayed.loaded.complete(saved);
    await flushing;
    final retained = await attributes.watchForSubmission('survey').first;
    expect(retained!.buildingName, 'Saved building');
    expect(retained.storeys, 4);
    expect((await submissions.findById('survey'))!.syncStatus, 'uploaded');
  });

  test('edits made before hydration survive disposal without blanking answers',
      () async {
    final saved = await attributes.watchForSubmission('survey').first;
    final delayed = _DelayedAttributes(db);
    final form = notifier(delayed)
      ..update((state) => state.copyWith(buildingName: 'Kept on exit'));
    final flushing = form.flushNow();
    form.dispose();
    delayed.loaded.complete(saved);
    await flushing;
    final retained = await attributes.watchForSubmission('survey').first;
    expect(retained!.buildingName, 'Kept on exit');
    expect(retained.storeys, 4);
    expect((await submissions.findById('survey'))!.syncStatus, 'in_progress');
  });

  test('explicit flush reports a failed write and retains the edit for retry',
      () async {
    final failing = _FailingAttributes(db);
    final form = notifier(failing)
      ..update((state) => state.copyWith(buildingName: 'Saved after retry'));
    await expectLater(form.flushNow(), throwsStateError);
    expect((await attributes.watchForSubmission('survey').first)!.buildingName,
        'Saved building',);
    failing.fail = false;
    await form.flushNow();
    expect((await attributes.watchForSubmission('survey').first)!.buildingName,
        'Saved after retry',);
    form.dispose();
  });

  test('a stale callback after disposal cannot overwrite saved answers',
      () async {
    final form = notifier(attributes);
    await form.flushNow();
    form
      ..dispose()
      ..update((state) => state.copyWith(buildingName: 'Stale callback'));
    await form.flushNow();
    final retained = await attributes.watchForSubmission('survey').first;
    expect(retained!.buildingName, 'Saved building');
    expect((await submissions.findById('survey'))!.syncStatus, 'uploaded');
  });
}
