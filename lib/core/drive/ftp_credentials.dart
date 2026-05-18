// lib/core/drive/ftp_credentials.dart
//
// Connection details the enumerator enters on the Get Maps screen for the
// FTP transport (Issue #45). Held in memory for the duration of one
// download; not persisted — the next session re-prompts. Persisting would
// need secure storage and a clear-credentials UX that's out of scope for
// this batch.
import 'package:flutter/foundation.dart';

@immutable
class FtpCredentials {
  const FtpCredentials({
    required this.host,
    required this.user,
    required this.password,
    required this.remotePath,
    this.port = 21,
  });

  final String host;
  final int port;
  final String user;
  final String password;

  /// Server-side folder that contains the per-assignment subfolders.
  /// Defaults to `/`. Each immediate child becomes a discoverable
  /// assignment, mirroring the Drive listing convention.
  final String remotePath;

  bool get isComplete =>
      host.isNotEmpty && user.isNotEmpty && password.isNotEmpty;
}
