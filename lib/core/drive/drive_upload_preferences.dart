import 'package:firecheck/core/security/secure_storage.dart';

class DriveUploadPreferences {
  DriveUploadPreferences(this._storage);
  final SecureStorage _storage;

  static const _keyAutoUpload = 'drive_auto_upload_enabled';

  Future<bool> isAutoUploadEnabled() async {
    final val = await _storage.read(_keyAutoUpload);
    return val == 'true';
  }

  Future<void> setAutoUploadEnabled({required bool enabled}) =>
      _storage.write(_keyAutoUpload, enabled ? 'true' : 'false');
}
