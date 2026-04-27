import 'package:firecheck/core/sync/domain/sync_outcome.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Success has no fields', () {
    expect(const Success(), isA<SyncOutcome>());
  });

  test('TransientFailure carries error', () {
    const o = TransientFailure('500 server error');
    expect(o, isA<SyncOutcome>());
    expect(o.error, '500 server error');
  });

  test('PermanentFailure carries error', () {
    const o = PermanentFailure('400 bad request');
    expect(o, isA<SyncOutcome>());
    expect(o.error, '400 bad request');
  });

  test('AuthExpired has no fields', () {
    expect(const AuthExpired(), isA<SyncOutcome>());
  });

  test('AssignmentClosed carries assignmentId', () {
    const o = AssignmentClosed('assignment-123');
    expect(o, isA<SyncOutcome>());
    expect(o.assignmentId, 'assignment-123');
  });
}
