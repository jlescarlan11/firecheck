import 'package:firecheck/core/errors/failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShapefileValidationFailure', () {
    test('carries message', () {
      const f = ShapefileValidationFailure("buildings.dbf is missing 'feat_id'");
      expect(f.message, contains('feat_id'));
      expect(f, isA<Failure>());
    });
  });

  group('NoAssignmentsFailure', () {
    test('has supervisor-guidance message', () {
      const f = NoAssignmentsFailure();
      expect(f.message, contains('supervisor'));
    });
  });
}
