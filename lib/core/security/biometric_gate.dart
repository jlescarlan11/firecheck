import 'package:local_auth/local_auth.dart';

class BiometricGate {
  BiometricGate([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  Future<bool> isAvailable() async {
    final deviceSupported = await _auth.isDeviceSupported();
    if (!deviceSupported) return false;
    return _auth.canCheckBiometrics;
  }

  /// Returns true if the user authenticated successfully.
  /// Returns false if they cancelled, failed, or biometrics is unavailable.
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          // biometricOnly defaults to false; allow device PIN/passcode
          // fallback so enumerators with dirty or wet hands in the field
          // can still unlock via their passcode.
          stickyAuth: true,
        ),
      );
    } on Exception {
      return false;
    }
  }
}
