import 'package:geolocator/geolocator.dart';

/// Narrow interface so widget tests can substitute a fake.
abstract class LocationService {
  /// Pure check — does NOT prompt the OS for permission. Use before
  /// showing a rationale dialog.
  Future<LocationPermission> checkPermission();

  /// Prompts the OS for permission if currently `denied`. Returns the
  /// post-prompt state.
  Future<LocationPermission> requestPermission();

  Future<bool> isLocationServiceEnabled();
  Stream<Position> positionStream();
  Future<Position?> lastKnownPosition();

  /// Opens the OS app settings page so the user can manually grant a
  /// previously deniedForever permission. Returns true if the page was
  /// successfully opened.
  Future<bool> openAppSettings();
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

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

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
}

/// In-memory fake for tests — emits whatever you seed, never touches
/// platform channels.
class FakeLocationService implements LocationService {
  FakeLocationService({
    this.checkPermissionResult = LocationPermission.whileInUse,
    this.requestPermissionResult = LocationPermission.whileInUse,
    this.serviceEnabled = true,
    this.positions = const Stream<Position>.empty(),
    this.lastKnown,
  });

  LocationPermission checkPermissionResult;
  LocationPermission requestPermissionResult;
  bool serviceEnabled;
  Stream<Position> positions;
  Position? lastKnown;

  /// Test recorder: flips to true the first time openAppSettings is called.
  bool openAppSettingsCalled = false;

  @override
  Future<LocationPermission> checkPermission() async => checkPermissionResult;

  @override
  Future<LocationPermission> requestPermission() async => requestPermissionResult;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Stream<Position> positionStream() => positions;

  @override
  Future<Position?> lastKnownPosition() async => lastKnown;

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCalled = true;
    return true;
  }
}
