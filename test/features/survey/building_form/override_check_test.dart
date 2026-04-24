import 'package:firecheck/features/survey/building_form/domain/override_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Brgy. Tisa rectangle (centroid ~10.31810, 123.88270).
  const ring = [
    [123.88200, 10.31720],
    [123.88340, 10.31720],
    [123.88340, 10.31900],
    [123.88200, 10.31900],
    [123.88200, 10.31720],
  ];

  test('user within 50m → TapAllowed', () async {
    final r = await checkTap(
      userLat: 10.31810,
      userLng: 123.88270,
      featureRing: ring,
      promptForReason: () async => fail('should not prompt'),
    );
    expect(r, isA<TapAllowed>());
  });

  test('user far away + reason → TapAllowedWithOverride', () async {
    final r = await checkTap(
      userLat: 10.40,
      userLng: 123.88,
      featureRing: ring,
      promptForReason: () async => 'polygon misplaced',
    );
    expect(r, isA<TapAllowedWithOverride>());
    expect((r as TapAllowedWithOverride).reason, 'polygon misplaced');
  });

  test('user far away + dismissed prompt → TapBlocked', () async {
    final r = await checkTap(
      userLat: 10.40,
      userLng: 123.88,
      featureRing: ring,
      promptForReason: () async => null,
    );
    expect(r, isA<TapBlocked>());
  });

  test('user far away + empty reason → TapBlocked', () async {
    final r = await checkTap(
      userLat: 10.40,
      userLng: 123.88,
      featureRing: ring,
      promptForReason: () async => '   ',
    );
    expect(r, isA<TapBlocked>());
  });
}
