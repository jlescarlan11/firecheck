import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section_providers.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/result/olp_result_screen.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders score hero + 4 progress bars + Mark Complete disabled',
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
          home: OlpResultScreen(submissionId: 's1', featureId: 'f1'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('0 / 35'), findsOneWidget);
    expect(find.text('Labis na Mapanganib'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(4));

    final btn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Mark survey complete'),
    );
    expect(btn.onPressed, isNull);

    // Acknowledge → button enables.
    const key = OlpFormKey(submissionId: 's1', featureId: 'f1');
    container
        .read(olpSectionNotifierProvider(key).notifier)
        .setHomeownerAcknowledged(acknowledged: true);
    await tester.pump();

    final btn2 = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Mark survey complete'),
    );
    expect(btn2.onPressed, isNotNull);

    await tester.pump(const Duration(milliseconds: 600));
    await db.close();
  });
}
