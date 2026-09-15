// Run with flutter test --no-pub --update-goldens tool/app_redesign_review_test.dart.
// Captures are written to build/ui-review for visual inspection.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_preferences.dart';
import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:firecheck/core/forms/form_definition.dart';
import 'package:firecheck/core/forms/form_definition_providers.dart';
import 'package:firecheck/core/location/location_providers.dart';
import 'package:firecheck/core/security/secure_storage.dart';
import 'package:firecheck/core/theme/app_theme.dart';
import 'package:firecheck/features/account/presentation/account_screen.dart';
import 'package:firecheck/features/assignment/domain/get_maps_state.dart'
    as maps;
import 'package:firecheck/features/assignment/presentation/assignment_closed_blocker.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/assignment/presentation/get_maps_screen.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:firecheck/features/auth/presentation/sign_in_screen.dart';
import 'package:firecheck/features/conflict_review/presentation/attribution_conflict_screen.dart';
import 'package:firecheck/features/conflict_review/presentation/conflict_review_list_screen.dart';
import 'package:firecheck/features/conflict_review/presentation/conflict_review_providers.dart';
import 'package:firecheck/features/conflict_review/presentation/dedup_review_screen.dart';
import 'package:firecheck/features/conflict_review/presentation/side_by_side_compare.dart';
import 'package:firecheck/features/form_preview/presentation/form_preview_screen.dart';
import 'package:firecheck/features/home/domain/progress_snapshot.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/home/presentation/home_screen.dart';
import 'package:firecheck/features/map/presentation/camera_target.dart';
import 'package:firecheck/features/map/presentation/map_providers.dart';
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:firecheck/features/map/presentation/map_screen.dart';
import 'package:firecheck/features/remote_activity/domain/remote_attribution_view.dart';
import 'package:firecheck/features/remote_activity/presentation/remote_activity_list_screen.dart';
import 'package:firecheck/features/remote_activity/presentation/remote_activity_providers.dart';
import 'package:firecheck/features/remote_activity/presentation/remote_attribution_detail_screen.dart';
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/domain/upload_progress.dart'
    as progress;
import 'package:firecheck/features/review/presentation/review_providers.dart'
    as review;
import 'package:firecheck/features/review/presentation/review_screen.dart';
import 'package:firecheck/features/survey/building_form/presentation/submission_detail_screen.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/olp_section.dart';
import 'package:firecheck/features/survey/olp_survey/presentation/result/olp_result_screen.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_notifier.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_screen.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart' show User, Session;

class _MapsNotifier extends StateNotifier<maps.GetMapsState>
    implements GetMapsNotifier {
  _MapsNotifier([maps.GetMapsState initial = const maps.Idle()])
      : super(initial);
  @override
  void reset() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Native Mapbox requires a device. This capture displays only real map controls.
class _PreviewMap implements MapRenderer {
  @override
  Widget build(
    BuildContext context, {
    required List<Feature> features,
    required String boundaryGeojson,
    required void Function(Feature) onFeatureTap,
    void Function(double, double, double)? onCameraChanged,
    bool sketchActive = false,
    void Function(double, double)? onMapTap,
    CameraTarget? cameraTarget,
    CameraTarget? initialCameraTarget,
    void Function(Feature)? onPolygonLongPress,
    String? reshapeWorkingPolygonGeojson,
    String? reshapeInvalidEdgeGeojson,
    void Function(MapProjection)? onProjectionReady,
    String? reshapingFeatureId,
  }) =>
      Container(
        color: const Color(0xFFF1F3F3),
        alignment: Alignment.center,
        child: const Padding(
          padding: EdgeInsets.all(48),
          child: Text('Map canvas omitted in widget preview',
              textAlign: TextAlign.center),
        ),
      );
}

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
  for (final width in [320.0, 390.0, 900.0]) {
    for (final entry in <String, Widget>{
      'home': const HomeScreen(),
      'sign-in': const SignInScreen(),
      'account': const AccountScreen(),
      'downloads': const GetMapsScreen(),
      'download-progress': const GetMapsScreen(),
      'uploads': const UploadQueueScreen(),
      'map-controls': const MapScreen(),
      'conflict-detail':
          const AttributionConflictScreen(submissionId: 's-building'),
      'duplicate': const DedupReviewScreen(featureId: 'building-1'),
      'household-form': Scaffold(
          appBar: AppBar(title: const Text('Household survey')),
          body: const SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: OlpSurveySection(
                  submissionId: 's-building', featureId: 'building-1'))),
      'review': const ReviewScreen(),
      'building': const SubmissionDetailScreen(featureId: 'building-1'),
      'road': const SubmissionDetailScreen(featureId: 'road-1'),
      'household-results': const OlpResultScreen(
        submissionId: 's-building',
        featureId: 'building-1',
      ),
      'form-rules': const FormPreviewScreen(),
      'activity': const RemoteActivityListScreen(),
      'their-answers':
          const RemoteAttributionDetailScreen(featureId: 'building-1'),
      'conflicts': const ConflictReviewListScreen(),
      'comparison': Scaffold(
        appBar: AppBar(title: const Text('Compare answers')),
        body: const SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: SideBySideCompare(
            mine: {
              'Building name': 'Barangay hall',
              'Storeys': 2,
              'Material': 'Concrete',
            },
            theirs: {
              'Building name': 'Barangay hall',
              'Storeys': 3,
              'Material': 'Concrete',
            },
            differingKeys: {'Storeys'},
          ),
        ),
      ),
      'assignment-closed': const AssignmentClosedBlocker(),
    }.entries) {
      testWidgets(
        '${entry.key} at $width',
        (tester) async {
          final db = AppDatabase.forTesting(NativeDatabase.memory());

          final now = DateTime(2026, 9, 15, 9, 30);
          await db.into(db.assignments).insert(
                AssignmentsCompanion.insert(
                  id: 'a1',
                  enumeratorId: 'demo-enumerator',
                  campaignId: 'c1',
                  boundaryPolygonGeojson: '{}',
                  createdAt: now,
                ),
              );
          for (final kind in ['building', 'road']) {
            await db.into(db.features).insert(
                  FeaturesCompanion.insert(
                    id: '$kind-1',
                    assignmentId: 'a1',
                    featureType: kind,
                    geometryGeojson: '{}',
                    createdAt: now,
                  ),
                );
            await db.into(db.submissions).insert(
                  SubmissionsCompanion.insert(
                    id: 's-$kind',
                    featureId: '$kind-1',
                    createdAt: now,
                    updatedAt: now,
                  ),
                );
          }
          final remote = RemoteAttributionView(
            id: 'remote-1',
            assignmentId: 'a1',
            featureId: 'building-1',
            featureType: 'building',
            attributeValues: {
              'building': {
                'building_name': 'Barangay hall',
                'storeys': 3,
                'material': 'Concrete',
              },
            },
            submittedBy: 'Juan Reyes',
            submittedAt: now,
            supersededAt: null,
            updatedAt: now,
          );

          tester.view.physicalSize = Size(width, width == 320 ? 640 : 844);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue =
              width == 320 ? 1.5 : 1;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                mapRendererProvider.overrideWithValue(_PreviewMap()),
                currentPositionProvider
                    .overrideWith((_) => const Stream.empty()),
                awaitingSubmissionsProvider
                    .overrideWith((_) => db.select(db.submissions).watch()),
                localAttributionForSubmissionProvider('s-building')
                    .overrideWith((_) async => {
                          'Building name': 'Barangay hall',
                          'Storeys': 2,
                          'Material': 'Concrete'
                        }),
                appDatabaseProvider.overrideWithValue(db),
                currentUserIdProvider.overrideWithValue('demo-enumerator'),
                currentFormDefinitionProvider
                    .overrideWith((_) async => FormDefinition.legacy),
                secureStorageProvider
                    .overrideWithValue(InMemorySecureStorage()),
                getMapsNotifierProvider.overrideWith((_) => _MapsNotifier(
                    entry.key == 'download-progress'
                        ? maps.DownloadingShapefiles(downloaded: 50, total: 100)
                        : const maps.Idle())),
                supabaseAuthStateProvider.overrideWith(
                  (_) => Stream.value(
                    Session(
                      accessToken: 'demo',
                      tokenType: 'bearer',
                      user: User(
                        id: 'demo',
                        appMetadata: {},
                        userMetadata: {'full_name': 'Maria Santos'},
                        aud: 'authenticated',
                        createdAt: now.toIso8601String(),
                        email: 'maria@example.com',
                      ),
                    ),
                  ),
                ),
                othersRemoteAttributionsProvider
                    .overrideWith((_) => Stream.value([remote])),
                remoteAttributionForFeatureProvider('building-1')
                    .overrideWith((_) => Stream.value(remote)),
                review.reviewStateProvider.overrideWithValue(
                  const AsyncData(
                    ReviewState(
                      summary: ReviewSummary(
                        totalFeatures: 60,
                        completeFeatures: 24,
                        incompleteFeatures: 36,
                        newFeaturesAdded: 2,
                        photosPending: 6,
                      ),
                      warnings: [],
                      blockers: [],
                      deadJobs: [],
                      upload: progress.Idle(),
                    ),
                  ),
                ),
                review.assignmentJobsStreamProvider
                    .overrideWith((_) => Stream.value([])),
                currentAssignmentProvider
                    .overrideWith((_) => Stream.value(null)),
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
                  (_) => Stream.value(
                    entry.key == 'assignment-closed'
                        ? const ClosedRemotely(bundleFile: null)
                        : const Unlocked(),
                  ),
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
          await tester.pumpAndSettle();
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpAndSettle();

          if (entry.key == 'household-form') {
            await tester.tap(find.byType(ExpansionTile).first);
            await tester.pumpAndSettle();
          }
          await expectLater(
            find.byType(Scaffold),
            matchesGoldenFile(
              '../build/ui-review/app-${entry.key}-${width.toInt()}.png',
            ),
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await db.close();
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );
    }
  }
}
