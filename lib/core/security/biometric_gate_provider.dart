import 'package:firecheck/core/security/biometric_gate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Riverpod handle on the singleton [BiometricGate]. Widget tests override
/// this with a `_FakeBiometricGate` (subclass returning fixed values) to
/// drive the Upload Data tap → biometric → navigate flow.
final biometricGateProvider = Provider<BiometricGate>((_) => BiometricGate());
