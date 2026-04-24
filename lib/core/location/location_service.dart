import 'package:geolocator/geolocator.dart';

/// Narrow interface so widget tests can substitute a fake.
abstract class LocationService {
  Future<LocationPermission> requestPermission();
  Future<bool> isLocationServiceEnabled();
  Stream<Position> positionStream();
  Future<Position?> lastKnownPosition();
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<LocationPermission> requestPermission() async {
    final existing = await Geolocator.checkPermission();
    if (existing == LocationPermission.denied) {
      return Geolocator.requestPermission();
    }
    return existing;
  }

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Stream<Position> positionStream() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        ),
      );

  @override
  Future<Position?> lastKnownPosition() => Geolocator.getLastKnownPosition();
}

/// In-memory fake for tests — emits whatever you seed, never touches
/// platform channels.
class FakeLocationService implements LocationService {
  FakeLocationService({
    this.permission = LocationPermission.whileInUse,
    this.serviceEnabled = true,
    this.positions = const Stream<Position>.empty(),
    this.lastKnown,
  });

  final LocationPermission permission;
  final bool serviceEnabled;
  final Stream<Position> positions;
  final Position? lastKnown;

  @override
  Future<LocationPermission> requestPermission() async => permission;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Stream<Position> positionStream() => positions;

  @override
  Future<Position?> lastKnownPosition() async => lastKnown;
}
