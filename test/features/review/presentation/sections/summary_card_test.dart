import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/presentation/sections/summary_card.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders all 5 stat rows', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SummaryCard(
            summary: ReviewSummary(
              totalFeatures: 7,
              completeFeatures: 5,
              incompleteFeatures: 2,
              newFeaturesAdded: 1,
              photosPending: 3,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('7'), findsWidgets);
    expect(find.textContaining('5'), findsWidgets);
    expect(find.textContaining('2'), findsWidgets);
    expect(find.textContaining('1'), findsWidgets);
    expect(find.textContaining('3'), findsWidgets);
  });
}
