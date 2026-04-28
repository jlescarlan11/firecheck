import 'package:firecheck/features/map/presentation/zoom_button.dart';
import 'package:firecheck/features/map/presentation/zoom_button_state.dart';
import 'package:firecheck/features/map/presentation/zoom_direction.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),);
    await tester.pump();
  }

  group('ZoomButton', () {
    testWidgets('zoomIn idle: renders + icon and tap invokes onTap',
        (tester) async {
      var taps = 0;
      await pump(
        tester,
        ZoomButton(
          direction: ZoomDirection.zoomIn,
          state: ZoomButtonState.idle,
          onTap: () => taps++,
        ),
      );
      expect(find.byIcon(Icons.add), findsOneWidget);

      await tester.tap(find.byType(ZoomButton));
      expect(taps, 1);
    });

    testWidgets('zoomOut idle: renders − icon and tap invokes onTap',
        (tester) async {
      var taps = 0;
      await pump(
        tester,
        ZoomButton(
          direction: ZoomDirection.zoomOut,
          state: ZoomButtonState.idle,
          onTap: () => taps++,
        ),
      );
      expect(find.byIcon(Icons.remove), findsOneWidget);

      await tester.tap(find.byType(ZoomButton));
      expect(taps, 1);
    });

    testWidgets('zoomIn disabled: opacity 0.5, taps do NOT invoke onTap',
        (tester) async {
      var taps = 0;
      await pump(
        tester,
        ZoomButton(
          direction: ZoomDirection.zoomIn,
          state: ZoomButtonState.disabled,
          onTap: () => taps++,
        ),
      );

      final opacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.byIcon(Icons.add),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 0.5);

      await tester.tap(find.byType(ZoomButton), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('zoomOut disabled: opacity 0.5, taps do NOT invoke onTap',
        (tester) async {
      var taps = 0;
      await pump(
        tester,
        ZoomButton(
          direction: ZoomDirection.zoomOut,
          state: ZoomButtonState.disabled,
          onTap: () => taps++,
        ),
      );

      final opacity = tester.widget<Opacity>(
        find.ancestor(
          of: find.byIcon(Icons.remove),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 0.5);

      await tester.tap(find.byType(ZoomButton), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('semantic labels: Zoom in / Zoom out', (tester) async {
      await pump(
        tester,
        ZoomButton(
          direction: ZoomDirection.zoomIn,
          state: ZoomButtonState.idle,
          onTap: () {},
        ),
      );
      expect(find.bySemanticsLabel('Zoom in'), findsOneWidget);

      await pump(
        tester,
        ZoomButton(
          direction: ZoomDirection.zoomOut,
          state: ZoomButtonState.idle,
          onTap: () {},
        ),
      );
      expect(find.bySemanticsLabel('Zoom out'), findsOneWidget);
    });
  });
}
