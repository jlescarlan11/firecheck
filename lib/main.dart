import 'package:firecheck/app.dart';
import 'package:firecheck/core/mapbox/offline_pack_adapter.dart';
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/map/presentation/map_providers.dart';
import 'package:firecheck/features/map/presentation/map_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
        mapRendererProvider.overrideWithValue(MapboxMapRenderer()),
        if (tileStore != null)
          offlinePackAdapterProvider.overrideWithValue(
            MapboxOfflinePackAdapter(tileStore),
          ),
      ],
      child: const FireCheckApp(),
    ),
  );
}
