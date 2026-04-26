import 'package:firecheck/features/survey/olp_survey/domain/olp_form_state.dart';
import 'package:firecheck/features/survey/olp_survey/domain/olp_form_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('homeownerAcknowledged=false → cannot mark complete', () {
    const s = OlpFormState(submissionId: 's1');
    final r = validateOlpForFinalize(s);
    expect(r.canMarkComplete, isFalse);
    expect(r.fieldErrors.keys, contains('homeownerAcknowledged'));
  });

  test('homeownerAcknowledged=true → can mark complete (no other gates)', () {
    const s = OlpFormState(submissionId: 's1', homeownerAcknowledged: true);
    final r = validateOlpForFinalize(s);
    expect(r.canMarkComplete, isTrue);
    expect(r.fieldErrors, isEmpty);
  });

  test('partial completion does not block finalize', () {
    const s = OlpFormState(
      submissionId: 's1',
      homeownerAcknowledged: true,
      checkedCodes: {'B-01'},
    );
    final r = validateOlpForFinalize(s);
    expect(r.canMarkComplete, isTrue);
  });
}
