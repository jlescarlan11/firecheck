import 'dart:convert';
import 'dart:io';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/photos/photo_capture_controller.dart';
import 'package:firecheck/core/photos/photo_providers.dart';
import 'package:firecheck/core/sync/domain/sync_outcome.dart';
import 'package:firecheck/features/survey/building_form/data/submission_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/survey_integration_fixture.dart';

void main() {
  for (final shared in [false, true]) {
    testWidgets(
        '${shared ? "shared" : "legacy"} sketch → required answer → camera → durable completion',
        (tester) async {
      final h = await SurveyIntegrationFixture.create();
      await seedIntegrationAssignment(h.db);
      if (shared) {
        await h.db.into(h.db.sharedMapCursors).insert(
            SharedMapCursorsCompanion.insert(
                accountId: integrationActor, assignmentId: 'a1',),);
        h.api.enqueueSubmitAttribution(
            outcome: const TransientFailure('offline'),);
      }
      await h.mount(tester);
      addTearDown(() => h.close(tester));
      await tester.runAsync(
          () => tester.tap(find.byKey(const Key('map.add-feature-pill'))),);
      await tester.pumpAndSettle();
      await tester.runAsync(() =>
          tester.tap(find.byKey(const Key('feature-type-picker.building'))),);
      await tester.pumpAndSettle();
      await h.renderer.simulateMapTap(1, 1);
      await h.renderer.simulateMapTap(2, 1);
      await h.renderer.simulateMapTap(2, 2);
      await tester.pump();
      await tester.runAsync(
          () => tester.tap(find.byKey(const Key('reshape.banner.save'))),);
      await h.until(
          tester,
          () =>
              find.widgetWithText(FilledButton, 'Done').evaluate().isNotEmpty,);
      await tester.pumpAndSettle();
      final features =
          await h.resolve(tester, () => h.db.select(h.db.features).get());
      final submissions =
          await h.resolve(tester, () => h.db.select(h.db.submissions).get());
      final feature = features.single;
      final submission = submissions.single;
      expect(feature.assignmentId, 'a1');
      expect(submission.submittedBy, integrationActor);
      expect(
          (jsonDecode(feature.geometryGeojson) as Map<String, dynamic>)['type'],
          'Polygon',);
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Done'))
              .onPressed,
          isNull,);
      await tester.enterText(
          find.byWidgetPredicate((w) =>
              w is TextField && w.decoration?.labelText == 'Building name *',),
          'Surveyed hall',);
      final controller = h.container.read(photoCaptureControllerProvider);
      expect(controller, isA<PhotoCaptureController>());
      await h.resolve(
          tester,
          () => controller.capture(
              submissionId: submission.id, featureId: feature.id,),);
      await h.until(
          tester,
          () =>
              tester
                  .widget<FilledButton>(
                      find.widgetWithText(FilledButton, 'Done'),)
                  .onPressed !=
              null,);
      h.navigation.popped.clear();
      await tester.runAsync(
          () => tester.tap(find.widgetWithText(FilledButton, 'Done')),);
      await h.until(tester, () => h.navigation.popped.isNotEmpty);
      await tester.pumpAndSettle();
      final reloaded = await h.resolve(
        tester,
        () async => (
          submission: await SubmissionRepository(h.db).findById(submission.id),
          feature: await h.db.select(h.db.features).getSingle(),
          photo: await h.db.select(h.db.photos).getSingle(),
          attrs: await h.db.select(h.db.buildingAttributes).getSingle(),
        ),
      );
      expect(reloaded.submission!.syncStatus,
          shared ? 'queued' : 'ready_to_upload',);
      expect(reloaded.submission!.id, submission.id);
      expect(reloaded.feature.status, 'complete');
      expect(reloaded.attrs.buildingName, 'Surveyed hall');
      expect(reloaded.photo.submissionId, submission.id);
      expect(File(reloaded.photo.localPath).existsSync(), isTrue);
      if (shared) {
        final jobs =
            await h.resolve(tester, () => h.db.select(h.db.syncJobs).get());
        expect(jobs.map((j) => j.entityType).toSet(),
            {'new_feature_upload', 'attribution_upload', 'photo'},);
        final attribution =
            jobs.firstWhere((j) => j.entityType == 'attribution_upload');
        expect(attribution.entityId, submission.id);
        expect(
            jobs
                .firstWhere((j) => j.entityType == 'new_feature_upload')
                .entityId,
            feature.id,);
        final frozen =
            jsonDecode(attribution.payloadJson!) as Map<String, dynamic>;
        expect((frozen['submission'] as Map)['submitted_by'], integrationActor);
      }
      await h.close(tester);
    });
  }
}
