import 'package:firecheck/core/drive/ftp_credentials.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FtpCredentials.isComplete requires host/user/password', () {
    expect(
      const FtpCredentials(
        host: '',
        user: 'u',
        password: 'p',
        remotePath: '/',
      ).isComplete,
      isFalse,
    );
    expect(
      const FtpCredentials(
        host: 'h',
        user: '',
        password: 'p',
        remotePath: '/',
      ).isComplete,
      isFalse,
    );
    expect(
      const FtpCredentials(
        host: 'h',
        user: 'u',
        password: '',
        remotePath: '/',
      ).isComplete,
      isFalse,
    );
    expect(
      const FtpCredentials(
        host: 'h',
        user: 'u',
        password: 'p',
        remotePath: '/',
      ).isComplete,
      isTrue,
    );
  });
}
