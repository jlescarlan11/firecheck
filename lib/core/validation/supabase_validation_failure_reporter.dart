import 'package:firecheck/core/validation/validation_failure_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseValidationFailureReporter implements ValidationFailureReporter {
  const SupabaseValidationFailureReporter({required this.supabase});
  final SupabaseClient supabase;

  @override
  Future<void> report({
    required String assignmentId,
    required String enumeratorId,
    required String failedRule,
    required String message,
    String? fileChecksum,
  }) async {
    try {
      await supabase.from('validation_failures').insert({
        'assignment_id': assignmentId,
        'enumerator_id': enumeratorId,
        'failed_rule': failedRule,
        'message': message,
        if (fileChecksum != null) 'file_checksum': fileChecksum,
      });
    } catch (_) {
      // Fire-and-forget — never block the enumerator-facing error display.
      debugPrint('[ValidationFailureReporter] Failed to log to Supabase');
    }
  }
}
