import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/forms/field_requirements.dart';
import 'package:firecheck/core/forms/field_requirements_providers.dart';
import 'package:firecheck/core/forms/form_definition.dart';
import 'package:firecheck/core/forms/form_definition_providers.dart';
import 'package:firecheck/core/forms/form_variant.dart';
import 'package:firecheck/core/forms/form_variant_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/building_form/domain/building_form_applicability.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/ff_facilities_section.dart';
import 'package:firecheck/features/survey/building_form/presentation/sections/identity_section.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mode in ['required', 'optional', 'omitted', 'hidden']) {
    testWidgets('CBMS and facilities labels follow $mode configuration',
        (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final requirements = parseFieldRequirements(
        mode == 'omitted'
            ? ''
            : 'building.cbmsId=$mode\nbuilding.fireFightingFacilities=$mode',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            fieldRequirementsProvider.overrideWithValue(requirements),
            currentFormDefinitionProvider
                .overrideWith((ref) async => FormDefinition.legacy),
            currentFormVariantProvider.overrideWithValue(
              FormVariant(
                id: 'test',
                name: 'Test',
                hideBuildingFields: mode == 'hidden'
                    ? {
                        BuildingFormField.cbmsId,
                        BuildingFormField.fireFightingFacilities,
                      }
                    : {},
              ),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    IdentitySection(
                      submissionId: 's',
                      featureId: 'f',
                      disabled: false,
                    ),
                    FfFacilitiesSection(
                      submissionId: 's',
                      featureId: 'f',
                      disabled: false,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final context = tester.element(find.byType(Scaffold));
      final l = AppLocalizations.of(context)!;
      final cbms = l.fieldCbmsId.replaceAll(RegExp(r'\s*\*\s*$'), '');
      final facilities =
          l.sectionFireFighting.replaceAll(RegExp(r'\s*\*\s*$'), '');
      if (mode == 'hidden') {
        expect(find.text(cbms), findsNothing);
        expect(find.text(facilities), findsNothing);
      } else {
        final suffix = mode == 'required' ? ' *' : '';
        expect(find.text('$cbms$suffix'), findsOneWidget);
        expect(find.text('$facilities$suffix'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      // Drain Drift's zero-duration stream cancellation timers in FakeAsync.
      await tester.pump(const Duration(milliseconds: 1));
      final closing = db.close();
      await tester.pump(const Duration(milliseconds: 1));
      await closing;
    });
  }
}
