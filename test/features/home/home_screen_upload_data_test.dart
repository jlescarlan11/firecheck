import 'package:firecheck/core/security/biometric_gate.dart';
import 'package:firecheck/core/security/biometric_gate_provider.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/home/domain/progress_snapshot.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/home/presentation/home_screen.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBiometric extends BiometricGate {
  _FakeBiometric({this.available = true, this.willAuthenticate = true});
  final bool available;
  final bool willAuthenticate;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate({required String reason}) async =>
      willAuthenticate;
}

void main() {
  testWidgets('SubmittedBanner replaces progress card when locked',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          progressProvider.overrideWith(
            (ref) => Stream.value(ProgressSnapshot.empty),
          ),
          assignmentLockStateProvider.overrideWith(
            (ref) =>
                Stream.value(Submitted(submittedAt: DateTime(2026, 4, 27))),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Submitted'), findsAtLeastNWidgets(1));
    expect(find.text('Upload Data'), findsNothing);
  });

  testWidgets('Upload Data tile shown when unlocked', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          progressProvider.overrideWith(
            (ref) => Stream.value(ProgressSnapshot.empty),
          ),
          assignmentLockStateProvider.overrideWith(
            (ref) => Stream.value(const Unlocked()),
          ),
          biometricGateProvider.overrideWithValue(_FakeBiometric()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Upload Data'), findsOneWidget);
  });
}
