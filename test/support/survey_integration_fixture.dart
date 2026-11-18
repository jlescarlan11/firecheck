import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:firecheck/core/auth/current_user_provider.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_api.dart';
import 'package:firecheck/core/drive/drive_upload_audit_repository.dart';
import 'package:firecheck/core/drive/drive_upload_providers.dart'
    hide driveUploadNotifierProvider;
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:firecheck/core/drive/enqueue_assignment_use_case.dart';
import 'package:firecheck/core/drive/finalize_assignment_upload_use_case.dart';
import 'package:firecheck/core/forms/field_requirements.dart';
import 'package:firecheck/core/forms/field_requirements_providers.dart';
import 'package:firecheck/core/forms/form_definition.dart';
import 'package:firecheck/core/forms/form_definition_providers.dart';
import 'package:firecheck/core/location/location_providers.dart';
import 'package:firecheck/core/photos/camera_service.dart';
import 'package:firecheck/core/photos/image_processor.dart';
import 'package:firecheck/core/photos/pending_photo_capture_store.dart';
import 'package:firecheck/core/photos/photo_capture_controller.dart';
import 'package:firecheck/core/photos/photo_providers.dart';
import 'package:firecheck/core/photos/photo_storage_service.dart';
import 'package:firecheck/core/security/secure_storage.dart';
import 'package:firecheck/core/sync/data/fake_sync_api.dart';
import 'package:firecheck/core/sync/domain/submit_attribution_result.dart';
import 'package:firecheck/core/sync/domain/sync_outcome.dart';
import 'package:firecheck/core/sync/presentation/sync_providers.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_exporter.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/map/presentation/map_providers.dart';
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:firecheck/features/map/presentation/map_screen.dart';
import 'package:firecheck/features/remote_activity/presentation/remote_activity_providers.dart';
import 'package:firecheck/features/review/presentation/review_providers.dart';
import 'package:firecheck/features/review/presentation/review_screen.dart';
import 'package:firecheck/features/survey/building_form/presentation/submission_detail_screen.dart';
import 'package:firecheck/features/survey/photo_capture/data/photo_repository.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

/// Assignment-scoped local seed shared by the UI integration tests.
const integrationBoundary =
    '{"type":"Polygon","coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]]]}';
const integrationActor = '00000000-0000-0000-0000-000000000001';

Future<void> seedIntegrationAssignment(
  AppDatabase db, {
  String boundary = integrationBoundary,
}) async {
  await db.into(db.assignments).insert(
        AssignmentsCompanion.insert(
          id: 'a1',
          enumeratorId: integrationActor,
          campaignId: 'c1',
          boundaryPolygonGeojson: boundary,
          downloadedAt: Value(DateTime.utc(2026)),
          createdAt: DateTime.utc(2026),
        ),
      );
}

Future<void> seedIntegrationSurvey(AppDatabase db) async {
  const geometry =
      '{"type":"Polygon","coordinates":[[[123.882,10.318],[123.883,10.318],[123.883,10.319],[123.882,10.318]]]}';
  await seedIntegrationAssignment(db, boundary: geometry);
  await db.into(db.features).insert(
        FeaturesCompanion.insert(
          id: 'f1',
          assignmentId: 'a1',
          featureType: 'building',
          status: const Value('complete'),
          geometryGeojson: geometry,
          createdAt: DateTime.utc(2026),
        ),
      );
  await db.into(db.submissions).insert(
        SubmissionsCompanion.insert(
          id: 's1',
          featureId: 'f1',
          submittedBy: const Value(integrationActor),
          syncStatus: const Value('ready_to_upload'),
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
}

class SurveyIntegrationFixture {
  SurveyIntegrationFixture(this.db, this.directory, this.source);
  final AppDatabase db;
  final Directory directory;
  final String source;
  final renderer = FakeMapRenderer();
  final navigation = RecordingNavigationObserver();
  final api = ControlledSyncApi();
  final drive = RecordingDriveApi();
  final audit = ControlledAudit();
  late ProviderContainer container;
  late GoRouter router;

  static Future<SurveyIntegrationFixture> create() async {
    final directory =
        Directory.systemTemp.createTempSync('survey_integration_');
    final source = '${directory.path}/camera.jpg';
    File(source)
        .writeAsBytesSync(img.encodeJpg(img.Image(width: 32, height: 24)));
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    return SurveyIntegrationFixture(db, directory, source);
  }

  static Future<SurveyIntegrationFixture> ready({required bool shared}) async {
    final h = await create();
    await seedIntegrationSurvey(h.db);
    await h.db.into(h.db.buildingAttributes).insert(
          BuildingAttributesCompanion.insert(
            submissionId: 's1',
            buildingName: const Value('Hall'),
            ra9514Type: const Value('C'),
          ),
        );
    if (shared) {
      await h.db.into(h.db.sharedMapCursors).insert(
            SharedMapCursorsCompanion.insert(
              accountId: integrationActor,
              assignmentId: 'a1',
            ),
          );
    }
    await h.capturePhoto('s1', 'f1');
    return h;
  }

  Future<String?> capturePhoto(String submissionId, String featureId) {
    final storage = InMemoryPhotoStorage(root: directory.path);
    return PhotoCaptureController(
      camera: FakeCameraService(scriptedPath: source),
      processor: const ImageProcessor(),
      storage: storage,
      repo: PhotoRepository(db: db, storage: storage),
      pendingStore: PendingPhotoCaptureStore(InMemorySecureStorage()),
    ).capture(submissionId: submissionId, featureId: featureId);
  }

  Future<void> mount(
    WidgetTester tester, {
    String route = '/map',
    List<Override> overrides = const [],
  }) async {
    tester.view.resetPhysicalSize();
    await tester.binding.setSurfaceSize(const Size(1000, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    router = GoRouter(
      initialLocation: route,
      observers: [navigation],
      routes: [
        GoRoute(path: '/map', builder: (_, __) => const MapScreen()),
        GoRoute(path: '/review', builder: (_, __) => const ReviewScreen()),
        GoRoute(
          path: '/feature/:featureId',
          builder: (_, state) => SubmissionDetailScreen(
            featureId: state.pathParameters['featureId']!,
            initialSubmissionId: state.uri.queryParameters['submission'],
          ),
        ),
      ],
    );
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        currentUserIdProvider.overrideWithValue(integrationActor),
        mapRendererProvider.overrideWithValue(renderer),
        syncApiProvider.overrideWithValue(api),
        currentPositionProvider.overrideWith((_) => const Stream.empty()),
        othersRemoteAttributionsProvider
            .overrideWith((_) => Stream.value(const [])),
        currentFormDefinitionProvider
            .overrideWith((_) async => FormDefinition.legacy),
        fieldRequirementsConfigProvider.overrideWith(
          (_) async => const FieldRequirements({
            FieldRequirementKeys.buildingRa9514Type: false,
            FieldRequirementKeys.buildingStoreys: false,
            FieldRequirementKeys.buildingMaterial: false,
            FieldRequirementKeys.buildingCost: false,
            FieldRequirementKeys.buildingFireLoad: false,
          }),
        ),
        cameraServiceProvider
            .overrideWithValue(FakeCameraService(scriptedPath: source)),
        photoStorageProvider
            .overrideWithValue(InMemoryPhotoStorage(root: directory.path)),
        secureStorageProvider.overrideWithValue(InMemorySecureStorage()),
        driveUploadAuditRepositoryProvider.overrideWithValue(audit),
        driveUploadWorkerProvider.overrideWith(
          (ref) => DriveUploadWorker(
            api: drive,
            currentUserId: () => integrationActor,
            repo: ref.watch(driveUploadRepoProvider),
            db: db,
            enumeratorIdentifier: () => integrationActor,
          ),
        ),
        enqueueAssignmentUseCaseProvider.overrideWith(
          (ref) => EnqueueAssignmentUseCase(
            db: db,
            repo: ref.watch(driveUploadRepoProvider),
            exporter: ShapefileExporter(db: db, tempDirOverride: directory),
            currentUserId: () => integrationActor,
          ),
        ),
        finalizeAssignmentUploadUseCaseProvider.overrideWith(
          (ref) => FinalizeAssignmentUploadUseCase(
            db: db,
            repo: ref.watch(driveUploadRepoProvider),
            assignmentRepo: ref.watch(assignmentRepositoryProvider),
            auditRepo: audit,
            enumeratorIdentifier: () => integrationActor,
          ),
        ),
        ...overrides,
      ],
    );
    await tester.runAsync(() async {
      await AssignmentRepository(db: db, userId: integrationActor)
          .selectAssignment('a1');
      await container.read(currentAssignmentProvider.future);
      await container.read(currentFormDefinitionProvider.future);
      await container.read(fieldRequirementsConfigProvider.future);
      await container.read(currentFeaturesProvider.future);
      await container.read(assignmentLockStateProvider.future);
      if (route == '/review') {
        await container
            .read(reviewSourceProvider.future)
            .timeout(const Duration(seconds: 5));
        await container
            .read(reviewFormDefinitionsProvider.future)
            .timeout(const Duration(seconds: 5));
        await container.read(assignmentUploadChangesProvider('a1').future);
        await container.read(sharedMapModeProvider.future);
      }
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    if (route.startsWith('/feature')) {
      await tester.pump();
    } else {
      await tester.pumpAndSettle();
    }
  }

  /// Awaits the actual asynchronous operation while allowing widget stream
  /// invalidations to run in Flutter's test zone.
  Future<T> resolve<T>(
    WidgetTester tester,
    Future<T> Function() operation,
  ) async {
    T? value;
    Object? failure;
    StackTrace? failureStack;
    var finished = false;
    await tester.runAsync(() async {
      unawaited(
        Future<T>.sync(operation).then<void>(
          (result) {
            value = result;
            finished = true;
          },
          onError: (Object error, StackTrace stack) {
            failure = error;
            failureStack = stack;
            finished = true;
          },
        ),
      );
    });
    await until(tester, () => finished);
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
    return value as T;
  }

  /// Pumps until an observable UI condition holds, yielding to the real DB
  /// executor rather than guessing a delay for asynchronous widget queries.
  Future<void> until(WidgetTester tester, bool Function() condition) async {
    await tester.runAsync(() async {
      final end = DateTime.now().add(const Duration(seconds: 5));
      while (!condition()) {
        if (DateTime.now().isAfter(end)) {
          throw StateError('UI condition not reached');
        }
        await tester.pump();
        await Future<void>(() {});
      }
    });
    await tester.pump();
  }

  bool _closed = false;
  Future<void> close(WidgetTester tester) async {
    if (_closed) return;
    _closed = true;
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    router.dispose();
    await tester.pump(const Duration(milliseconds: 1));
    var closed = false;
    final closing = db.close().then((_) {
      closed = true;
    });
    await until(tester, () => closed);
    await closing;
    directory.deleteSync(recursive: true);
    await tester.pump(const Duration(milliseconds: 1));
  }
}

class RecordingDriveApi implements DriveUploadApi {
  @override
  Future<DriveUploadApi> forAccount(String accountId) async => this;
  final List<String> files = [];
  final List<String> acceptedPaths = [];
  bool offline = false;
  @override
  Future<String> findOrCreateFirecheckRoot() async => 'root';
  @override
  Future<String> createOrGetFolder(String name, String parentId) async =>
      '$parentId/$name';
  @override
  Future<String> uploadFile({
    required String localPath,
    required String driveParentId,
    required String fileName,
    String? resumableUri,
    void Function(int, int)? onProgress,
  }) async {
    if (offline) throw const SocketException('offline');
    expect(await File(localPath).length(), greaterThan(0));
    files.add(fileName);
    acceptedPaths.add(localPath);
    return 'drive-${files.length}';
  }
}

class ControlledAudit extends DriveUploadAuditRepository {
  ControlledAudit()
      : super(
          SupabaseClient(
            'http://localhost',
            'test-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );
  final List<String> accepted = [];
  @override
  Future<AuditProbeResult> listForAssignment(String assignmentId) async =>
      const AuditProbeAvailable([]);
  @override
  Future<void> record({
    required String assignmentId,
    required String uploadedBy,
    required String driveFolderPath,
    required String driveFolderUrl,
    required int fileCount,
  }) async {
    accepted.add('$assignmentId/$uploadedBy');
  }
}

class ControlledSyncApi extends FakeSyncApi {
  Future<void> Function()? beforeAttribution;
  @override
  Future<({SyncOutcome outcome, SubmitAttributionResult? result})>
      submitAttribution({
    required Map<String, dynamic> payload,
    String? baseVersionId,
  }) async {
    await beforeAttribution?.call();
    return super
        .submitAttribution(payload: payload, baseVersionId: baseVersionId);
  }
}

class RecordingNavigationObserver extends NavigatorObserver {
  final List<Route<dynamic>> popped = [];
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped.add(route);
    super.didPop(route, previousRoute);
  }
}
