import 'dart:io';

import 'package:firecheck/features/assignment/presentation/assignment_lock_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Unlocked equality', () {
    expect(const Unlocked(), const Unlocked());
  });

  test('Submitted carries submittedAt', () {
    final s1 = Submitted(submittedAt: DateTime(2026, 4, 27));
    final s2 = Submitted(submittedAt: DateTime(2026, 4, 27));
    expect(s1.submittedAt, s2.submittedAt);
  });

  test('ClosedRemotely carries optional bundleFile', () {
    const c1 = ClosedRemotely(bundleFile: null);
    final c2 = ClosedRemotely(bundleFile: File('/tmp/x.zip'));
    expect(c1.bundleFile, isNull);
    expect(c2.bundleFile?.path, '/tmp/x.zip');
  });
}
