import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/survey/photo_capture/presentation/photo_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/survey_integration_fixture.dart';

void main() {
  for (final owner in ['other-user', null, '']) {
    testWidgets(
        'accepted tab owned by $owner is viewable but form photo and Done are guarded',
        (tester) async {
      final h = (await tester
          .runAsync(() => SurveyIntegrationFixture.ready(shared: false)))!;
      await tester.runAsync(() async {
        await h.db.update(h.db.submissions).write(
              SubmissionsCompanion(
                submittedBy: Value(owner),
                syncStatus: const Value('uploaded'),
              ),
            );
      });
      await h.mount(tester, route: '/feature/f1?submission=s1');
      addTearDown(() => h.close(tester));
      final name = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Building name *',
      );
      await h.until(tester, () => name.evaluate().isNotEmpty);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(name).enabled, isFalse);
      final ignore = find
          .ancestor(
            of: find.byType(PhotoStrip),
            matching: find.byType(IgnorePointer),
          )
          .first;
      expect(tester.widget<IgnorePointer>(ignore).ignoring, isTrue);
      expect(find.widgetWithText(FilledButton, 'Done'), findsNothing);
      final saved = await h.resolve(
        tester,
        () => h.db.select(h.db.submissions).getSingle(),
      );
      expect(saved.submittedBy, owner);
      expect(saved.syncStatus, 'uploaded');
      expect(
        await h.resolve(tester, () => h.db.select(h.db.syncJobs).get()),
        isEmpty,
      );
      await h.close(tester);
    });
  }
}
