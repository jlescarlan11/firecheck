// lib/core/drive/transport_source_factory.dart
//
// Strategy seam for picking the active map-source transport (Issue #45).
// Google Drive is injected (so isolates/tests can swap in fakes); FTP is
// built on demand from in-memory credentials. Both paths flow through
// resolve() so the calling notifier no longer needs to know how either
// transport is constructed.
import 'package:firecheck/core/drive/drive_api.dart';
import 'package:firecheck/core/drive/ftp_credentials.dart';
import 'package:firecheck/core/drive/ftp_map_source_api.dart';
import 'package:firecheck/core/drive/transport_source.dart';

class TransportSourceFactory {
  TransportSourceFactory({required this.driveApi});

  final DriveApi driveApi;

  DriveApi resolve(TransportSource transport, {FtpCredentials? ftp}) {
    switch (transport) {
      case TransportSource.googleDrive:
        return driveApi;
      case TransportSource.ftp:
        final c = ftp;
        if (c == null || !c.isComplete) {
          throw StateError(
            'FTP transport selected but credentials are missing — fill in '
            'the host/user/password fields before starting.',
          );
        }
        return FtpMapSourceApi(c);
    }
  }
}
