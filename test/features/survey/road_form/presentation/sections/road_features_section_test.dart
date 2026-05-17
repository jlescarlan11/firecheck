import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/forms/form_variant.dart';
import 'package:firecheck/core/forms/form_variant_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/survey/road_form/presentation/sections/_road_features_section.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('othersDescription field appears only when "others" is checked',
      (tester) async {
    // Create the DB *inside* the testWidgets callback so that it lives in the
    // FakeAsync zone.  Every Drift Lock.synchronized() call made during the
    // test will then create Completer futures whose _zone is the FakeAsync
    // zone, which allows flushMicrotasks() to drain them without deadlocking.
    final db = AppDatabase.forTesting(NativeDatabase.memory());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          // Bypass the async asset load so no pending Future survives the
          // test's drain — the FutureProvider would otherwise still be in
          // flight when the widget tree disposes.
          currentFormVariantProvider
              .overrideWithValue(FormVariant.defaultVariant),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: RoadFeaturesSection(
              submissionId: 's1',
              featureId: 'f1',
              disabled: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Vendor stalls'), findsOneWidget);
    expect(find.text('Describe other features'), findsNothing);

    await tester.tap(find.text('Others'));
    await tester.pump();

    expect(find.text('Describe other features'), findsOneWidget);

    // Advance FakeAsync time past the 500 ms debounce window.  This fires
    // RoadFormNotifier's debounce Timer (which is captured by FakeAsync) and
    // causes _flush() to run its DB operations inside the FakeAsync zone,
    // where flushMicrotasks() can drain them.  Without this step the timer
    // would still be pending when _verifyInvariants() runs and the test
    // would fail with "A Timer is still pending".
    await tester.pump(const Duration(milliseconds: 600));
  });
}
