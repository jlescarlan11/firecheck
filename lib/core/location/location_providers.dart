import 'package:firecheck/core/location/location_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  return const GeolocatorLocationService();
});

/// Keeps current fixes available, including accuracy updates while stationary.
final currentPositionProvider = StreamProvider.autoDispose<Position>((ref) {
  return ref.watch(locationServiceProvider).positionStream();
});
