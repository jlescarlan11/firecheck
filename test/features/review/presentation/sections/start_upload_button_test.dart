import 'package:firecheck/features/review/presentation/sections/start_upload_button.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('confirmed unchanged work shows Uploaded and cannot be tapped',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
          body: StartUploadButton(
        enabled: false,
        alreadyUploaded: true,
        onPressed: () => fail('Must not reupload'),
      )),
    ));
    expect(find.text('Uploaded'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });

  testWidgets('disabled with blockers', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StartUploadButton(enabled: false, onPressed: () {}),
        ),
      ),
    );
    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNull);
  });

  testWidgets('enabled when ready, fires onPressed', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StartUploadButton(enabled: true, onPressed: () => pressed++),
        ),
      ),
    );
    await tester.tap(find.byType(FilledButton));
    expect(pressed, 1);
  });
}
