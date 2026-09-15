import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:firecheck/core/forms/form_definition.dart';
import 'package:firecheck/core/forms/form_definition_providers.dart';
import 'package:firecheck/features/form_preview/presentation/form_preview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('previews rule visibility against geometry controls',
      (tester) async {
    const definition = FormDefinition(
      version: '2',
      name: 'Preview',
      visibilityRules: [
        FormVisibilityRule(
          target: 'building.section.large',
          conditions: [
            FormCondition(
              source: 'geometry',
              key: 'areaSqMeters',
              comparison: FormComparison.greaterThanOrEqual,
              value: 500,
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentFormDefinitionProvider.overrideWith((ref) => definition),
        ],
        child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: FormPreviewScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hidden'), findsOneWidget);
    await tester.drag(
        find.byKey(const Key('form-preview-area')), const Offset(500, 0));
    await tester.pump();
    expect(find.text('Visible'), findsOneWidget);
  });
}
