import 'dart:convert';

import 'package:firecheck/core/security/secure_storage.dart';

class PendingPhotoCapture {
  const PendingPhotoCapture({
    required this.submissionId,
    required this.featureId,
  });

  final String submissionId;
  final String featureId;
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
      if (submissionId is! String ||
          submissionId.isEmpty ||
          featureId is! String ||
          featureId.isEmpty) {
        return null;
      }
      return PendingPhotoCapture(
        submissionId: submissionId,
        featureId: featureId,
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> clear() => _storage.delete(_key);
}
