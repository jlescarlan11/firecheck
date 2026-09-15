import 'dart:convert';

import 'package:firecheck/core/security/secure_storage.dart';

class PendingPhotoCapture {
  const PendingPhotoCapture({
    required this.submissionId,
    required this.featureId,
    this.recoveredSourcePath,
  });

  final String submissionId;
  final String featureId;

  /// Path retained after ImagePicker lost-data retrieval until the image has
  /// been processed and inserted durably. This makes a failed recovery
  /// retryable instead of consuming the only ImagePicker result.
  final String? recoveredSourcePath;
}

/// Persists the form context before Android hands control to the camera app.
/// The OS may destroy FireCheck while the camera activity is in front, so
/// in-memory state cannot be the source of truth for lost-data recovery.
class PendingPhotoCaptureStore {
  PendingPhotoCaptureStore(this._storage);

  final SecureStorage _storage;
  static const _key = 'pending_photo_capture';

  Future<void> save(PendingPhotoCapture capture) {
    return _storage.write(
      _key,
      jsonEncode({
        'submission_id': capture.submissionId,
        'feature_id': capture.featureId,
        if (capture.recoveredSourcePath != null)
          'recovered_source_path': capture.recoveredSourcePath,
      }),
    );
  }

  Future<PendingPhotoCapture?> read() async {
    final raw = await _storage.read(_key);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) return null;
      final submissionId = value['submission_id'];
      final featureId = value['feature_id'];
      final recoveredSourcePath = value['recovered_source_path'];
      if (submissionId is! String ||
          submissionId.isEmpty ||
          featureId is! String ||
          featureId.isEmpty) {
        return null;
      }
      return PendingPhotoCapture(
        submissionId: submissionId,
        featureId: featureId,
        recoveredSourcePath:
            recoveredSourcePath is String && recoveredSourcePath.isNotEmpty
                ? recoveredSourcePath
                : null,
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> clear() => _storage.delete(_key);
}
