import 'package:firecheck/app.dart';
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

  runApp(const ProviderScope(child: FireCheckApp()));
}
