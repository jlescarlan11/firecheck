import 'package:firecheck/core/drive/drive_upload_preferences.dart';
import 'package:firecheck/core/security/secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('autoUploadEnabled defaults to false', () async {
    final prefs = DriveUploadPreferences(InMemorySecureStorage());
    expect(await prefs.isAutoUploadEnabled(), isFalse);
  });

  test('setAutoUpload persists and reads back', () async {
    final prefs = DriveUploadPreferences(InMemorySecureStorage());
    await prefs.setAutoUploadEnabled(enabled: true);
    expect(await prefs.isAutoUploadEnabled(), isTrue);
    await prefs.setAutoUploadEnabled(enabled: false);
    expect(await prefs.isAutoUploadEnabled(), isFalse);
  });
}
