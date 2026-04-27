import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_rubric.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section_providers.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/scored_section_widget.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Section D renders 5 CheckboxListTiles + tapping toggles state',
      (tester) async {
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

    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ScoredSectionWidget(
              section: OlpSection.d,
              submissionId: 's1',
              featureId: 'f1',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CheckboxListTile), findsNWidgets(5));

    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();

    const key = OlpFormKey(submissionId: 's1', featureId: 'f1');
    final state = container.read(olpSectionNotifierProvider(key));
    expect(state.checkedCodes, contains('D-25'));

    await tester.pump(const Duration(milliseconds: 600));
    await db.close();
  });
}
