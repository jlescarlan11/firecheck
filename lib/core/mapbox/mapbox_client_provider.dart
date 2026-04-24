import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Marker provider — returns true once MapboxOptions.setAccessToken has been
/// called in main.dart. Consumers depend on this to guarantee init order.
/// Not a real "client" — the Mapbox Flutter SDK exposes its surface via
/// static calls (MapWidget, OfflineManager) rather than a per-client instance.
final mapboxInitializedProvider = Provider<bool>((ref) {
  return true;
});
