import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/road_form/presentation/road_form.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders all 3 sections + does-not-exist switch', (tester) async {
    // Create DB INSIDE the test body (FakeAsync zone) — see deadlock note.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: RoadForm(submissionId: 's1', featureId: 'f1'),
          ),
        ),
      ),
    );
    await tester.pump();

    // SectionCard renders titles via .toUpperCase() — match actual rendered text.
    expect(find.text('ROAD IDENTITY'), findsOneWidget);
    expect(find.text('DIMENSIONS'), findsOneWidget);
    expect(find.text('FEATURES'), findsOneWidget);
    expect(find.text('This road does not exist'), findsOneWidget);

    // Drain pending debounce timer so the test framework doesn't complain.
    await tester.pump(const Duration(milliseconds: 600));

    await db.close();
  });
}
