/// Base sealed class for expected, recoverable failure modes surfaced from
/// repositories to the UI. Unknown/unexpected exceptions should propagate
/// as regular `Object` errors and be caught by the app-level error zone.
sealed class Failure implements Exception {
  const Failure(this.message);
  final String message;

  @override
  // Debug/log output only; user-facing text should always come from
  // [message]. runtimeType may be minified in release builds, which is
  // acceptable here since this string never reaches end users.
  // ignore: no_runtimetype_tostring
  String toString() => '$runtimeType($message)';
}

/// Network / offline / remote-unavailable.
class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Network unavailable']);
}

/// Auth failed (bad credentials, expired token, biometric denied).
class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

/// Storage / DB / filesystem problem.
class StorageFailure extends Failure {
  const StorageFailure(super.message);
}

/// Validation — input data rejected by local or server rules.
class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {this.fieldErrors = const {}});
  final Map<String, String> fieldErrors;
}

/// Server rejected the request with a permanent 4xx (except 401/409).
class ServerRejectedFailure extends Failure {
  const ServerRejectedFailure(super.message, this.statusCode);
  final int statusCode;
}

/// The assignment was closed remotely (409).
class AssignmentClosedFailure extends Failure {
  const AssignmentClosedFailure()
      : super('This assignment was closed by your supervisor.');
}

/// Shapefile import rejected by the validation pipeline.
class ShapefileValidationFailure extends Failure {
  const ShapefileValidationFailure(super.message, {required this.ruleName});
  // Short identifier for the failing rule — sent to Supabase, never shown to the enumerator.
  final String ruleName;
}

/// /firecheck/ has no assignment subfolders accessible to the signed-in user.
class NoAssignmentsFailure extends Failure {
  const NoAssignmentsFailure()
      : super(
          'No assignments shared with you yet — ask your supervisor to share '
          'the assignment folder with the Google account you signed in with.',
        );
}
