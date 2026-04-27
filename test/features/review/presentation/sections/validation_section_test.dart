import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/presentation/sections/validation_section.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hidden when no issues', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ValidationSection(
            issues: const [],
            severity: ReviewSeverity.blocker,
            onGoToFeature: (_) {},
          ),
        ),
      ),
    );
    expect(find.textContaining('fix before upload'), findsNothing);
  });

  testWidgets('groups issues by feature, shows Go-to-feature link', (tester) async {
    String? tappedFeature;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ValidationSection(
            issues: const [
              ReviewIssue(
                featureId: 'f-1',
                featureLabel: 'Building 123abc',
                severity: ReviewSeverity.blocker,
                code: 'photo_required',
                messageKey: 'issuePhotoRequired',
              ),
            ],
            severity: ReviewSeverity.blocker,
            onGoToFeature: (id) => tappedFeature = id,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Must fix before upload'), findsOneWidget);
    expect(find.text('Building 123abc'), findsOneWidget);
    expect(find.textContaining('photo'), findsOneWidget);

    await tester.tap(find.text('Go to feature'));
    expect(tappedFeature, 'f-1');
  });
}
