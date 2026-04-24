import 'package:firecheck/features/map/presentation/feature_too_far_modal.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap() {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (ctx) {
            return TextButton(
              onPressed: () =>
                  showFeatureTooFarModal(ctx, distanceMeters: 87),
              child: const Text('open'),
            );
          },
        ),
      ),
    );
  }

  testWidgets('modal shows distance + continue + cancel', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('87m'), findsOneWidget);
    expect(find.text('Continue anyway'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });
}
