import 'package:firecheck/core/security/biometric_gate.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';

class _MockLocalAuth extends Mock implements LocalAuthentication {}

void main() {
  setUpAll(() {
    registerFallbackValue(const AuthenticationOptions());
  });

  group('BiometricGate', () {
    late _MockLocalAuth mockAuth;
    late BiometricGate gate;

    setUp(() {
      mockAuth = _MockLocalAuth();
      gate = BiometricGate(mockAuth);
    });

    test('isAvailable returns false when device does not support biometrics',
        () async {
      when(() => mockAuth.isDeviceSupported()).thenAnswer((_) async => false);
      when(() => mockAuth.canCheckBiometrics).thenAnswer((_) async => false);

      expect(await gate.isAvailable(), isFalse);
    });

    test('isAvailable returns true when device supports biometrics', () async {
      when(() => mockAuth.isDeviceSupported()).thenAnswer((_) async => true);
      when(() => mockAuth.canCheckBiometrics).thenAnswer((_) async => true);

      expect(await gate.isAvailable(), isTrue);
    });

    test('authenticate returns true on success', () async {
      when(
        () => mockAuth.authenticate(
          localizedReason: any(named: 'localizedReason'),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => true);

      expect(await gate.authenticate(reason: 'Unlock'), isTrue);
    });

    test('authenticate returns false when user cancels or fails', () async {
      when(
        () => mockAuth.authenticate(
          localizedReason: any(named: 'localizedReason'),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => false);

      expect(await gate.authenticate(reason: 'Unlock'), isFalse);
    });

    test('authenticate returns false when local_auth throws', () async {
      when(
        () => mockAuth.authenticate(
          localizedReason: any(named: 'localizedReason'),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        PlatformException(code: 'NotAvailable', message: 'biometrics disabled'),
      );

      expect(await gate.authenticate(reason: 'Unlock'), isFalse);
    });
  });
}
