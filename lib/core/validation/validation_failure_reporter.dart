abstract class ValidationFailureReporter {
  Future<void> report({
    required String assignmentId,
    required String enumeratorId,
    required String failedRule,
    required String message,
    String? fileChecksum,
  });
}

class FakeValidationFailureReporter implements ValidationFailureReporter {
  final calls = <Map<String, String?>>[];

  @override
  Future<void> report({
    required String assignmentId,
    required String enumeratorId,
    required String failedRule,
    required String message,
    String? fileChecksum,
  }) async {
    calls.add({
      'assignmentId': assignmentId,
      'enumeratorId': enumeratorId,
      'failedRule': failedRule,
      'message': message,
      'fileChecksum': fileChecksum,
    });
  }
}
