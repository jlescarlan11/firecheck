import 'package:firecheck/features/map/presentation/recenter_button.dart';
import 'package:firecheck/features/map/presentation/recenter_button_state.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ));
    await tester.pump();
  }

  group('RecenterButton', () {
    testWidgets('idle: renders my_location icon and tap invokes onTap',
        (tester) async {
      var taps = 0;
      await pump(
        tester,
        RecenterButton(
          state: RecenterButtonState.idle,
          onTap: () => taps++,
        ),
      );
      expect(find.byIcon(Icons.my_location), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.byType(RecenterButton));
      expect(taps, 1);
    });

    testWidgets('loading: renders spinner; taps do NOT invoke onTap',
        (tester) async {
      var taps = 0;
      await pump(
        tester,
        RecenterButton(
          state: RecenterButtonState.loading,
          onTap: () => taps++,
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.my_location), findsNothing);

      await tester.tap(find.byType(RecenterButton), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('disabled: renders icon at reduced opacity; no taps',
        (tester) async {
      var taps = 0;
      await pump(
        tester,
        RecenterButton(
          state: RecenterButtonState.disabled,
          onTap: () => taps++,
        ),
      );
      expect(find.byIcon(Icons.my_location), findsOneWidget);

      // Disabled rendering wraps the button in an Opacity of 0.5.
      final opacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.byIcon(Icons.my_location),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 0.5);

      await tester.tap(find.byType(RecenterButton), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('has the recenterButtonSemanticLabel semantic label',
        (tester) async {
      await pump(
        tester,
        RecenterButton(
          state: RecenterButtonState.idle,
          onTap: () {},
        ),
      );
      expect(
        find.bySemanticsLabel('Recenter map on my location'),
        findsOneWidget,
      );
    });
  });
}
