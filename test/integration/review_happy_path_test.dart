import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/presentation/sync_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/review/domain/upload_progress.dart';
import 'package:firecheck/features/review/presentation/review_providers.dart';
import 'package:firecheck/features/review/presentation/review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/survey_integration_fixture.dart';

void main() {
  for (final shared in [false, true]) {
    testWidgets(
        'Review UI uses real ${shared ? 'shared sync' : 'legacy export'} orchestration and captured ownership',
        (tester) async {
      final h = (await tester.runAsync(() async {
        final h = await SurveyIntegrationFixture.create();
        await seedIntegrationSurvey(h.db);
        await h.db.into(h.db.buildingAttributes).insert(
              BuildingAttributesCompanion.insert(
                submissionId: 's1',
                buildingName: const Value('Hall'),
                ra9514Type: const Value('C'),
              ),
            );
        if (shared) {
          await h.db.into(h.db.sharedMapCursors).insert(
                SharedMapCursorsCompanion.insert(
                  accountId: integrationActor,
                  assignmentId: 'a1',
                ),
              );
        }
        await h.capturePhoto('s1', 'f1');
        return h;
      }))!;
      await h.mount(tester, route: '/review');
      addTearDown(() => h.close(tester));
      expect(
        h.container
            .read(reviewStateProvider)
            .requireValue
            .blockers
            .map((b) => b.code),
        isEmpty,
      );
      await h.until(
        tester,
        () => find
            .widgetWithText(
              FilledButton,
              shared ? 'Sync changes' : 'Start Upload',
            )
            .evaluate()
            .isNotEmpty,
      );
      await h.until(
        tester,
        () =>
            tester
                .widget<FilledButton>(
                  find.widgetWithText(
                    FilledButton,
                    shared ? 'Sync changes' : 'Start Upload',
                  ),
                )
                .onPressed !=
            null,
      );
      await tester.runAsync(
        () => tester.tap(
          find.widgetWithText(
            FilledButton,
            shared ? 'Sync changes' : 'Start Upload',
          ),
        ),
      );
      await h.until(
        tester,
        () => shared
            ? h.api.markPhotoUploadedCalls.isNotEmpty &&
                find.textContaining('synced').evaluate().isNotEmpty
            : h.audit.accepted.isNotEmpty &&
                h.container.read(uploadProgressControllerProvider('a1'))
                    is Idle,
      );
      await tester.pump();
      expect(h.api.submitAttributionCalls, hasLength(1));
      final payload =
          h.api.submitAttributionCalls.single.payload['submission'] as Map;
      expect(payload['submitted_by'], integrationActor);
      expect(payload['feature_id'], 'f1');
      final rows = await h.resolve(
        tester,
        () async => (
          submission: await h.db.select(h.db.submissions).getSingle(),
          photo: await h.db.select(h.db.photos).getSingle(),
          driveJobs: await h.db.select(h.db.driveUploadJobs).get(),
        ),
      );
      expect(rows.submission.syncStatus, 'uploaded');
      expect(rows.photo.uploadStatus, 'uploaded');
      expect(File(rows.photo.localPath).existsSync(), isTrue);
      if (shared) {
        expect(h.drive.files, isEmpty);
        expect(rows.driveJobs, isEmpty);
      } else {
        expect(h.drive.files, isNotEmpty);
        expect(
          rows.driveJobs.every(
            (j) => j.assignmentId == 'a1' && j.ownerId == integrationActor,
          ),
          isTrue,
        );
        expect(h.audit.accepted, ['a1/$integrationActor']);
      }
      expect(h.container.read(isAssignmentLockedProvider), isFalse);
      if (find.byType(SnackBar).evaluate().isNotEmpty) {
        ScaffoldMessenger.of(tester.element(find.byType(ReviewScreen)))
            .clearSnackBars();
        await tester.pumpAndSettle();
      }
      // Edit the already accepted tab through the actual form and Done flow.
      unawaited(h.router.push('/feature/f1?submission=s1'));
      final nameField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Building name *',
      );
      await h.until(
        tester,
        () =>
            nameField.evaluate().isNotEmpty &&
            find.widgetWithText(FilledButton, 'Done').evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(nameField).enabled, isTrue);
      final reopened = await h.resolve(tester, () => h.db.select(h.db.submissions).get());
      expect(reopened, hasLength(1), reason: 'Opening accepted work is not a new observation');
      expect(reopened.single.updatedAt, rows.submission.updatedAt);

      await tester.enterText(nameField, 'Hall revision two');
      await tester.runAsync(
        () => tester.tap(find.widgetWithText(FilledButton, 'Done')),
      );
      await h.until(
        tester,
        () => find.byType(ReviewScreen).evaluate().isNotEmpty,
      );
      if (shared) {
        await h.until(
          tester,
          () =>
              h.api.submitAttributionCalls.length == 2 &&
              find.text('Up to date').evaluate().isNotEmpty,
        );
      } else {
        await h.until(
          tester,
          () =>
              find
                  .widgetWithText(FilledButton, 'Start Upload')
                  .evaluate()
                  .isNotEmpty &&
              tester
                      .widget<FilledButton>(
                        find.widgetWithText(FilledButton, 'Start Upload'),
                      )
                      .onPressed !=
                  null,
        );
        await tester.runAsync(
          () => tester.tap(find.widgetWithText(FilledButton, 'Start Upload')),
        );
        await h.until(
          tester,
          () =>
              h.audit.accepted.length == 2 &&
              h.container.read(uploadProgressControllerProvider('a1')) is Idle,
        );
      }
      expect(h.api.submitAttributionCalls, hasLength(2));
      final revised = h.api.submitAttributionCalls.last.payload;
      expect(
        (revised['building_attributes'] as Map)['building_name'],
        'Hall revision two',
      );
      expect(
        revised['operation_id'],
        isNot(h.api.submitAttributionCalls.first.payload['operation_id']),
      );
      // Retrying the same accepted operation never submits another operation.
      await h.resolve(
        tester,
        () => h.container.read(syncControllerProvider).triggerNow(),
      );
      expect(h.api.submitAttributionCalls, hasLength(2));
      await h.resolve(tester, () async {
        await h.db
            .update(h.db.assignments)
            .write(const AssignmentsCompanion(closedRemotely: Value(true)));
      });
      unawaited(h.router.push('/feature/f1?submission=s1'));
      await h.until(
        tester,
        () =>
            nameField.evaluate().isNotEmpty &&
            h.container.read(isAssignmentLockedProvider),
      );
      expect(tester.widget<TextField>(nameField).enabled, isFalse);
      expect(find.widgetWithText(FilledButton, 'Done'), findsNothing);
      await h.close(tester);
    });
  }
}
