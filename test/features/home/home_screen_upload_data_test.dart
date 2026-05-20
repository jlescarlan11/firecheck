import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:firecheck/core/security/biometric_gate.dart';
import 'package:firecheck/core/security/biometric_gate_provider.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/home/domain/progress_snapshot.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/home/presentation/home_screen.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_notifier.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBiometric extends BiometricGate {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> authenticate({required String reason}) async => true;
}

void main() {
  testWidgets('Submitted shows the banner but keeps Upload Data available',
      (tester) async {
    // Submitted is informational, not a hard lock — enumerators may
    // re-export and re-upload after a submit.
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
          biometricGateProvider.overrideWithValue(_FakeBiometric()),
          driveUploadNotifierProvider.overrideWith(
            (_) => DriveUploadNotifier.seeded(const DriveUploadState(jobs: [])),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Submitted'), findsAtLeastNWidgets(1));
    expect(find.text('Upload Data'), findsOneWidget);
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
          driveUploadNotifierProvider.overrideWith(
            (_) => DriveUploadNotifier.seeded(const DriveUploadState(jobs: [])),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Upload Data'), findsOneWidget);
  });

  testWidgets('Upload Data tile hidden when ClosedRemotely', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          progressProvider.overrideWith(
            (ref) => Stream.value(ProgressSnapshot.empty),
          ),
          assignmentLockStateProvider.overrideWith(
            (ref) => Stream.value(const ClosedRemotely(bundleFile: null)),
          ),
          driveUploadNotifierProvider.overrideWith(
            (_) => DriveUploadNotifier.seeded(const DriveUploadState(jobs: [])),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Upload Data'), findsNothing);
  });
}
