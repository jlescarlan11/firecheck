import 'package:firecheck/features/review/domain/upload_progress.dart';
import 'package:firecheck/features/review/presentation/sections/upload_progress_section.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('InProgress shows progress bar with done/total label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: UploadProgressSection(
            progress: const InProgress(done: 2, total: 5),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('2'), findsWidgets);
    expect(find.textContaining('5'), findsWidgets);
  });

  testWidgets('Completed(0) shows success message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: UploadProgressSection(progress: const Completed(failedCount: 0)),
        ),
      ),
    );
    expect(find.textContaining('uploaded'), findsOneWidget);
  });

  testWidgets('Idle/Locked render nothing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: UploadProgressSection(progress: Idle())),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
