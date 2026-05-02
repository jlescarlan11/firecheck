import 'package:firecheck/app.dart';
import 'package:firecheck/core/device/storage_checker.dart';
import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:firecheck/core/drive/drive_upload_workmanager.dart';
import 'package:firecheck/core/drive/google_drive_api.dart';
import 'package:firecheck/core/mapbox/offline_pack_adapter.dart';
import 'package:firecheck/core/sync/presentation/sync_providers.dart';
import 'package:firecheck/core/sync/shapefile/dbf_parser.dart';
import 'package:firecheck/core/sync/shapefile/reprojector.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_importer.dart';
import 'package:firecheck/core/sync/worker/workmanager_dispatcher.dart';
import 'package:firecheck/core/validation/supabase_validation_failure_reporter.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_providers.dart';
import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/auth/data/google_sign_in_auth_repository.dart';
import 'package:firecheck/features/auth/presentation/google_auth_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/map/presentation/map_providers.dart';
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _googleSignIn = GoogleSignIn(
  scopes: [
    'https://www.googleapis.com/auth/drive.readonly',
    'https://www.googleapis.com/auth/drive.file',
  ],
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load();
  final supaUrl = dotenv.env['SUPABASE_URL'];
  final supaKey = dotenv.env['SUPABASE_ANON_KEY'];
  final mapboxToken = dotenv.env['MAPBOX_ACCESS_TOKEN'];
  if (supaUrl == null || supaUrl.isEmpty ||
      supaKey == null || supaKey.isEmpty) {
    throw StateError(
      'SUPABASE_URL / SUPABASE_ANON_KEY missing from .env. '
      'Copy .env.example to .env and fill in real values.',
    );
  }
  if (mapboxToken == null || mapboxToken.isEmpty) {
    throw StateError(
      'MAPBOX_ACCESS_TOKEN missing from .env. '
      'Add your Mapbox public token (pk.…) to .env.',
    );
  }

  await Supabase.initialize(url: supaUrl, anonKey: supaKey);
  await registerPeriodicSync();
  await registerPeriodicDriveUpload();
  MapboxOptions.setAccessToken(mapboxToken);

  // Phase 1 T19: wire the real Mapbox renderer + offline-pack adapter so
  // production builds use the live SDK. Tests and widget-tests still get
  // the Fake defaults via `map_providers.dart` / `assignment_providers.dart`.
  //
  // TileStore.createDefault() is a best-effort: on a fresh install before
  // the native side is fully warm it can throw. If that happens we simply
  // fall through and leave `offlinePackAdapterProvider` on its Fake default,
  // so the app still launches.
  TileStore? tileStore;
  try {
    tileStore = await TileStore.createDefault();
  } on Object {
    tileStore = null;
  }

  runApp(
    ProviderScope(
      overrides: [
        googleSignInProvider.overrideWithValue(_googleSignIn),
        mapRendererProvider.overrideWithValue(MapboxMapRenderer()),
        if (tileStore != null)
          offlinePackAdapterProvider.overrideWithValue(
            MapboxOfflinePackAdapter(tileStore),
          ),
        googleAuthRepositoryProvider.overrideWith(
          (ref) => GoogleSignInAuthRepository(
            googleSignIn: _googleSignIn,
            secureStorage: const FlutterSecureStorage(),
          ),
        ),
        driveApiProvider.overrideWith(
          (ref) => GoogleDriveApi(
            googleSignIn: _googleSignIn,
          ),
        ),
        shapefileImporterProvider.overrideWith(
          (ref) => ShapefileImporter(
            db: ref.watch(appDatabaseProvider),
            dbfParser: const DbfParser(),
            reprojector: Reprojector(),
          ),
        ),
        storageCheckerProvider.overrideWithValue(const DeviceStorageChecker()),
        validationFailureReporterProvider.overrideWithValue(
          SupabaseValidationFailureReporter(
            supabase: Supabase.instance.client,
          ),
        ),
      ],
      child: const _DriveUploadBootstrap(
        child: _SyncBootstrap(child: FireCheckApp()),
      ),
    ),
  );
}

class _DriveUploadBootstrap extends ConsumerStatefulWidget {
  const _DriveUploadBootstrap({required this.child});
  final Widget child;

  @override
  ConsumerState<_DriveUploadBootstrap> createState() =>
      _DriveUploadBootstrapState();
}

class _DriveUploadBootstrapState extends ConsumerState<_DriveUploadBootstrap> {
  @override
  void initState() {
    super.initState();
    Future.microtask(_boot);
  }

  Future<void> _boot() async {
    final controller = ref.read(driveUploadControllerProvider);
    await controller.start();
    _watchForCompletion();
  }

  void _watchForCompletion() {
    ref.read(assignmentLockStateProvider.stream).listen((state) async {
      if (state is! Submitted) return;
      final repo = ref.read(assignmentRepositoryProvider);
      final assignment = await repo.getCurrentAssignment();
      if (assignment == null) return;
      await ref.read(enqueueAssignmentUseCaseProvider).execute(
            assignmentId: assignment.id,
          );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _SyncBootstrap extends ConsumerStatefulWidget {
  const _SyncBootstrap({required this.child});
  final Widget child;

  @override
  ConsumerState<_SyncBootstrap> createState() => _SyncBootstrapState();
}

class _SyncBootstrapState extends ConsumerState<_SyncBootstrap> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(syncControllerProvider).start();
      _attachSubmittedLock();
    });
  }

  void _attachSubmittedLock() {
    // Pull the current assignment lazily and kick off the watcher.
    // Subscription lives for the rest of the app session.
    Future.microtask(() async {
      final repo = ref.read(assignmentRepositoryProvider);
      final assignment = await repo.getCurrentAssignment();
      if (assignment == null) return;
      ref
          .read(submittedAssignmentLockProvider)
          .watchAndStamp(assignment.id)
          .listen((_) {});
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
