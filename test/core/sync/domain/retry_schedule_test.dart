import 'package:firecheck/core/sync/domain/retry_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixedNow = DateTime(2026, 4, 26, 12);

  test('attempts=1 → 30 seconds later', () {
    expect(nextRetryAt(1, now: fixedNow), fixedNow.add(const Duration(seconds: 30)));
  });

  test('attempts=2 → 2 minutes later', () {
    expect(nextRetryAt(2, now: fixedNow), fixedNow.add(const Duration(minutes: 2)));
  });

  test('attempts=3 → 10 minutes later', () {
    expect(nextRetryAt(3, now: fixedNow), fixedNow.add(const Duration(minutes: 10)));
  });

  test('attempts=4 → 1 hour later', () {
    expect(nextRetryAt(4, now: fixedNow), fixedNow.add(const Duration(hours: 1)));
  });

  test('attempts=5 → null (dead)', () {
    expect(nextRetryAt(5, now: fixedNow), isNull);
  });

  test('attempts=99 → null (dead)', () {
    expect(nextRetryAt(99, now: fixedNow), isNull);
  });
}
