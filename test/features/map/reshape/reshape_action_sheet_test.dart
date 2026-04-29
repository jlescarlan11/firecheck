import 'package:firecheck/features/map/reshape/presentation/reshape_action_sheet.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: child,
    );

void main() {
  testWidgets('returns openForm on Open form tap', (tester) async {
    ReshapeAction? r;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (ctx) {
            return TextButton(
              onPressed: () async {
                r = await showReshapeActionSheet(ctx, locked: false);
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reshape.actionsheet.openForm')));
    await tester.pumpAndSettle();
    expect(r, ReshapeAction.openForm);
  });

  testWidgets('returns reshape on Reshape tap', (tester) async {
    ReshapeAction? r;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (ctx) {
            return TextButton(
              onPressed: () async {
                r = await showReshapeActionSheet(ctx, locked: false);
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reshape.actionsheet.reshape')));
    await tester.pumpAndSettle();
    expect(r, ReshapeAction.reshape);
  });

  testWidgets('Reshape item disabled when locked', (tester) async {
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (ctx) {
            return TextButton(
              onPressed: () async {
                await showReshapeActionSheet(ctx, locked: true);
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final tile = tester.widget<ListTile>(
      find.byKey(const Key('reshape.actionsheet.reshape')),
    );
    expect(tile.enabled, isFalse);
  });
}
