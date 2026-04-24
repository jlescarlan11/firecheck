import 'package:firecheck/core/location/location_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  return const GeolocatorLocationService();
});

/// Re-emits whenever device position changes (filtered at 3m).
final currentPositionProvider = StreamProvider<Position>((ref) {
  return ref.watch(locationServiceProvider).positionStream();
});
