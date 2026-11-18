import 'dart:async';

import 'package:firecheck/app.dart';
import 'package:firecheck/core/device/storage_checker.dart';
import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:firecheck/core/drive/drive_upload_workmanager.dart';
import 'package:firecheck/core/drive/google_drive_api.dart';
import 'package:firecheck/core/gateway/gateway_map_source.dart';
import 'package:firecheck/core/gateway/gateway_providers.dart';
import 'package:firecheck/core/mapbox/offline_pack_adapter.dart';
import 'package:firecheck/core/sync/presentation/remote_cache_providers.dart';
import 'package:firecheck/core/sync/presentation/sync_providers.dart';
import 'package:firecheck/core/sync/shapefile/dbf_parser.dart';
import 'package:firecheck/core/sync/shapefile/reprojector.dart';
import 'package:firecheck/core/sync/shapefile/shapefile_importer.dart';
import 'package:firecheck/core/sync/worker/workmanager_dispatcher.dart';
import 'package:firecheck/core/validation/supabase_validation_failure_reporter.dart';
import 'package:firecheck/features/assignment/data/assignment_name_resolver.dart';
import 'package:firecheck/features/assignment/data/canonical_feature_publisher.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/auth/data/caching_google_auth_repository.dart';
import 'package:firecheck/features/auth/data/google_access_token_cache.dart';
import 'package:firecheck/features/auth/data/google_sign_in_auth_repository.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/map/presentation/map_providers.dart';
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load();
  final supaUrl = dotenv.env['SUPABASE_URL'];
  final supaKey = dotenv.env['SUPABASE_ANON_KEY'];
  final mapboxToken = dotenv.env['MAPBOX_ACCESS_TOKEN'];
  final googleWebClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'];
  if (supaUrl == null ||
      supaUrl.isEmpty ||
      supaKey == null ||
      supaKey.isEmpty) {
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
  if (googleWebClientId == null || googleWebClientId.isEmpty) {
    throw StateError(
      'GOOGLE_WEB_CLIENT_ID missing from .env. '
      'Add the Web OAuth client ID from Google Cloud Console.',
    );
  }

  await Supabase.initialize(url: supaUrl, anonKey: supaKey);
  await GoogleSignIn.instance.initialize(serverClientId: googleWebClientId);
  await registerPeriodicSync();
  await registerPeriodicDriveUpload();
  MapboxOptions.setAccessToken(mapboxToken);

  TileStore? tileStore;
  try {
    tileStore = await TileStore.createDefault();
  } on Object {
    tileStore = null;
  }

  runApp(
    ProviderScope(
      overrides: [
        googleAuthRepositoryProvider.overrideWith(
          (ref) => CachingGoogleAuthRepository(
            inner: GoogleSignInAuthRepository(
              auth: Supabase.instance.client.auth,
              googleSignIn: GoogleSignIn.instance,
              requireDriveConsent: configuredGatewayUri() == null,
            ),
            cache: SecureStorageGoogleAccessTokenCache(
              ref.watch(secureStorageProvider),
            ),
          ),
        ),
        driveApiProvider.overrideWith(
          (ref) {
            final gateway = ref.watch(gatewayClientProvider);
            return gateway != null
                ? GatewayMapSource(gateway)
                : GoogleDriveApi(
                    googleAuthRepo: ref.watch(googleAuthRepositoryProvider),
                  );
          },
        ),
        mapRendererProvider.overrideWithValue(MapboxMapRenderer()),
        if (tileStore != null)
          offlinePackAdapterProvider.overrideWithValue(
            MapboxOfflinePackAdapter(tileStore),
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
        assignmentNameResolverProvider.overrideWithValue(
          configuredGatewayUri() != null
              ? const NoopAssignmentNameResolver()
              : SupabaseAssignmentNameResolver(Supabase.instance.client),
        ),
        canonicalFeaturePublisherProvider.overrideWith(
          (ref) => SupabaseCanonicalFeaturePublisher(
            client: Supabase.instance.client,
            db: ref.watch(appDatabaseProvider),
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
  StreamSubscription<AuthState>? _authSub;
  bool _remoteStarted = false;
  int _remoteGeneration = 0;
  StreamSubscription<dynamic>? _submittedSub;
  Future<void> _selectionChange = Future.value();
  String? _observedAssignmentId;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(syncControllerProvider).start();
      _wireRemoteSyncToAuth();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _submittedSub?.cancel();
    super.dispose();
  }

  /// Cold-open full pull plus realtime subscription with connection state
  /// machine. Must be (re)evaluated on every auth state change — the common
  /// flow is app launch → sign-in screen → user signs in, so a one-shot
  /// check at `initState` would never fire start() for that session and the
  /// cache would stay empty until app restart.
  void _wireRemoteSyncToAuth() {
    final client = Supabase.instance.client;
    if (client.auth.currentSession != null) {
      unawaited(_startRemoteSync());
    }
    _authSub = client.auth.onAuthStateChange.listen((event) {
      if (event.session != null) {
        unawaited(_startRemoteSync());
      } else {
        _stopRemoteSync();
      }
    });
  }

  Future<void> _startRemoteSync() async {
    if (_remoteStarted) return;
    _remoteStarted = true;
    final generation = ++_remoteGeneration;
    final cache = ref.read(remoteCacheControllerProvider);
    final wiring = ref.read(realtimeWiringProvider);
    final realtime = ref.read(realtimeSyncControllerProvider);
    await cache.start();
    if (!mounted || generation != _remoteGeneration) return;
    wiring.start();
    await realtime.start();
  }

  void _stopRemoteSync() {
    if (!_remoteStarted) return;
    _remoteStarted = false;
    _remoteGeneration++;
    // Invalidate so the controllers' onDispose hooks (which call stop())
    // run, and the next sign-in starts from fresh instances.
    ref
      ..invalidate(realtimeSyncControllerProvider)
      ..invalidate(realtimeWiringProvider)
      ..invalidate(remoteCacheControllerProvider);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentAssignmentProvider, (_, next) {
      if (next.isLoading) return;
      final id = next.valueOrNull?.id;
      if (id == _observedAssignmentId) return;
      _observedAssignmentId = id;
      _selectionChange = _selectionChange.then((_) async {
        if (!mounted) return;
        await _submittedSub?.cancel();
        _submittedSub = null;
        _stopRemoteSync();
        if (id == null) return;
        _submittedSub = ref
            .read(submittedAssignmentLockProvider)
            .watchAndStamp(id)
            .listen((_) {});
        await _startRemoteSync();
      }).catchError((Object error) {
        debugPrint("Could not refresh selected map: $error");
      });
    });
    return widget.child;
  }
}
