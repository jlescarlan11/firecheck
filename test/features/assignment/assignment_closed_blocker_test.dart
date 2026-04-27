import 'dart:io';

import 'package:firecheck/features/assignment/presentation/assignment_closed_blocker.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders title + body when ClosedRemotely', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assignmentLockStateProvider.overrideWith(
            (_) => Stream.value(const ClosedRemotely(bundleFile: null)),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AssignmentClosedBlocker(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Assignment closed'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing); // no bundle yet
  });

  testWidgets('renders Share button when bundle file present', (tester) async {
    final tempFile = File('${Directory.systemTemp.path}/dummy-bundle.zip')
      ..writeAsBytesSync(const [1, 2, 3]);
    addTearDown(tempFile.deleteSync);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assignmentLockStateProvider.overrideWith(
            (_) => Stream.value(ClosedRemotely(bundleFile: tempFile)),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AssignmentClosedBlocker(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.textContaining('Share bundle'), findsOneWidget);
  });

  testWidgets('returns SizedBox.shrink when not closed', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assignmentLockStateProvider.overrideWith(
            (_) => Stream.value(const Unlocked()),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AssignmentClosedBlocker(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Assignment closed'), findsNothing);
  });
}
