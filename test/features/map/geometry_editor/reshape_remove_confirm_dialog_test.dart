import 'package:firecheck/features/map/geometry_editor/presentation/reshape_remove_confirm_dialog.dart';
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
  testWidgets('confirm tap returns true', (tester) async {
    bool? result;
    await tester.pumpWidget(_wrap(Builder(builder: (ctx) {
      return TextButton(
        onPressed: () async {
          result = await showReshapeRemoveConfirm(ctx, currentRingLength: 5);
        },
        child: const Text('open'),
      );
    },),),);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reshape.remove.confirm')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('cancel tap returns false', (tester) async {
    bool? result;
    await tester.pumpWidget(_wrap(Builder(builder: (ctx) {
      return TextButton(
        onPressed: () async {
          result = await showReshapeRemoveConfirm(ctx, currentRingLength: 5);
        },
        child: const Text('open'),
      );
    },),),);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reshape.remove.cancel')));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('confirm disabled at 3 vertices', (tester) async {
    await tester.pumpWidget(_wrap(Builder(builder: (ctx) {
      return TextButton(
        onPressed: () async {
          await showReshapeRemoveConfirm(ctx, currentRingLength: 3);
        },
        child: const Text('open'),
      );
    },),),);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final btn = tester.widget<FilledButton>(
      find.byKey(const Key('reshape.remove.confirm')),
    );
    expect(btn.onPressed, isNull);
  });
}
