// Run with flutter test --no-pub --update-goldens tool/home_redesign_review_test.dart.
// Captures are written to build/ui-review for visual inspection.
import 'dart:io';

import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_preferences.dart';
import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:firecheck/core/security/secure_storage.dart';
import 'package:firecheck/core/theme/app_theme.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/conflict_review/presentation/conflict_review_providers.dart';
import 'package:firecheck/features/home/domain/progress_snapshot.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/home/presentation/home_screen.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_notifier.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  setUpAll(() async {
    final artifacts =
        p.dirname(p.dirname(p.dirname(Platform.resolvedExecutable)));
    final loader = FontLoader('Roboto');
    for (final weight in ['Regular', 'Bold']) {
      loader.addFont(
        File(p.join(artifacts, 'material_fonts', 'Roboto-$weight.ttf'))
            .readAsBytes()
            .then(ByteData.sublistView),
      );
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        File(p.join(artifacts, 'material_fonts', 'MaterialIcons-Regular.otf'))
            .readAsBytes()
            .then(ByteData.sublistView),
      );
    await icons.load();
  });
  for (final width in [390.0, 900.0]) {
    for (final entry in <String, Widget>{
      'home': const HomeScreen(),
    }.entries) {
      testWidgets('${entry.key} at $width', (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentAssignmentProvider.overrideWith((_) => Stream.value(null)),
              awaitingResolutionCountProvider.overrideWithValue(0),
              progressProvider.overrideWith(
                (_) => Stream.value(
                  const ProgressSnapshot(
                    totalFeatures: 60,
                    completedFeatures: 24,
                    inProgressFeatures: 5,
                    queuedJobs: 0,
                    failedJobs: 0,
                    deadJobs: 0,
                  ),
                ),
              ),
              assignmentLockStateProvider.overrideWith(
                (_) => Stream.value(const Unlocked()),
              ),
              driveUploadNotifierProvider.overrideWith(
                (_) =>
                    // ignore: invalid_use_of_visible_for_testing_member
                    DriveUploadNotifier.seeded(
                  DriveUploadState(
                    jobs: List.generate(
                      6,
                      (i) => DriveUploadJob(
                        id: 'demo-$i',
                        assignmentId: 'demo',
                        filePath: '/demo/photo-$i.jpg',
                        fileType: DriveFileType.photo,
                        fileName: 'photo-$i.jpg',
                        fileSizeBytes: 1024,
                        capturedAt: DateTime(2026, 9, 15),
                        status: DriveUploadJobStatus.pending,
                        retryCount: 0,
                        createdAt: DateTime(2026, 9, 15),
                      ),
                    ),
                  ),
                ),
              ),
              driveUploadPreferencesProvider.overrideWithValue(
                DriveUploadPreferences(InMemorySecureStorage()),
              ),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildAppTheme(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: entry.value,
            ),
          ),
        );
        await tester.runAsync(() async {
          await precacheImage(
            const AssetImage('assets/icon/app_icon.png'),
            tester.element(find.byType(Scaffold)),
          );
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            '../build/ui-review/home-redesign-${width.toInt()}.png',
          ),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
