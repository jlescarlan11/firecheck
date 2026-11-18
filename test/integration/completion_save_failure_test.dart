import 'package:firecheck/features/survey/building_form/data/building_attributes_repository.dart';
import 'package:firecheck/features/survey/building_form/presentation/building_form_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/survey_integration_fixture.dart';

class _FailingAttributes extends BuildingAttributesRepository {
  _FailingAttributes(super.db);
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
  }) async {
    throw StateError('disk unavailable');
  }
}

void main() {
  testWidgets(
      'Done preserves the editable form and reports a failed durable save',
      (tester) async {
    final h = (await tester
        .runAsync(() => SurveyIntegrationFixture.ready(shared: false)))!;
    await h.mount(
      tester,
      route: '/feature/f1?submission=s1',
      overrides: [
        buildingAttributesRepositoryProvider
            .overrideWithValue(_FailingAttributes(h.db)),
      ],
    );
    addTearDown(() => h.close(tester));
    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Building name *',
    );
    await h.until(
      tester,
      () =>
          field.evaluate().isNotEmpty &&
          find.widgetWithText(FilledButton, 'Done').evaluate().isNotEmpty &&
          tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, 'Done'),
                  )
                  .onPressed !=
              null,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Done'))
          .onPressed,
      isNotNull,
    );
    await tester.enterText(field, 'Unsaved edit');
    await tester.pump();
    await tester
        .runAsync(() => tester.tap(find.widgetWithText(FilledButton, 'Done')));
    await h.until(
      tester,
      () => find
          .text('Could not save this survey. Please try again.')
          .evaluate()
          .isNotEmpty,
    );
    expect(field, findsOneWidget);
    expect(
      (await h.resolve(
        tester,
        () => h.db.select(h.db.buildingAttributes).getSingle(),
      ))
          .buildingName,
      'Hall',
    );
    expect(
      await h.resolve(tester, () => h.db.select(h.db.syncJobs).get()),
      isEmpty,
    );
    await h.close(tester);
  });
}
