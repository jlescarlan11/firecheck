// lib/core/drive/ftp_map_source_api.dart
//
// FTP transport for the Get Maps flow (Issue #45). Implements [DriveApi]
// so the existing GetMapsNotifier pipeline works unchanged: list
// assignments, get total size, stream a download. Upload is not supported
// — FieldData upload still runs through Google Drive.
//
// Protocol: bare-bones RFC 959 over plain TCP — LIST + PASV + RETR — so
// no external dependency is required. Tested manually against vsftpd and
// FileZilla Server. Passive mode only; active mode is rare on mobile
// networks where the device can't accept inbound connections.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firecheck/core/drive/drive_api.dart';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';
import 'package:firecheck/core/drive/ftp_credentials.dart';

class FtpMapSourceApi implements DriveApi {
  FtpMapSourceApi(this.credentials);
  final FtpCredentials credentials;

  @override
  Future<List<DriveAssignment>> listAssignments() async {
    final c = await _FtpClient.connect(credentials);
    try {
      final entries = await c.list(credentials.remotePath);
      // Each immediate child directory becomes an assignment, mirroring
      // the Drive convention (driveFolderId stored as the path).
      return entries
          .where((e) => e.isDir)
          .map(
            (e) => DriveAssignment(
              assignmentId: e.name,
              // FTP LIST timestamps are best-effort; use the empty
              // string — the notifier's delta check is purely an
              // optimization and tolerates this.
              inputZipModifiedTime: '',
              driveFolderId: _joinPath(credentials.remotePath, e.name),
            ),
          )
          .toList(growable: false);
    } finally {
      await c.close();
    }
  }

  @override
  Future<int> getTotalSize(String assignmentId) async {
    final c = await _FtpClient.connect(credentials);
    try {
      final folder = _joinPath(credentials.remotePath, assignmentId);
      final entries = await c.list(folder);
      var total = 0;
      for (final e in entries) {
        if (!e.isDir) total += e.size;
      }
      return total;
    } finally {
      await c.close();
    }
  }

  @override
  Stream<DriveDownloadEvent> downloadShapefiles(String assignmentId) async* {
    final c = await _FtpClient.connect(credentials);
    try {
      final folder = _joinPath(credentials.remotePath, assignmentId);
      final entries = await c.list(folder);
      final fileEntries = entries.where((e) => !e.isDir).toList(growable: false);
      final total = fileEntries.fold<int>(0, (a, e) => a + e.size);
      final files = <String, Uint8List>{};
      var downloaded = 0;
      for (final e in fileEntries) {
        final bytes = await c.retrieve(_joinPath(folder, e.name));
        files[e.name.toLowerCase()] = bytes;
        downloaded += bytes.length;
        yield DriveDownloadProgress(
          downloaded: downloaded,
          total: total == 0 ? downloaded : total,
        );
      }
      // FTP doesn't carry per-file checksums in this minimal client. The
      // validator's checksum rule treats missing entries as "skip" rather
      // than fatal, matching the Drive path's "no md5 from API" branch.
      yield DriveDownloadComplete(files, const {});
    } finally {
      await c.close();
    }
  }

  @override
  Future<({String folderPath, String folderUrl})> uploadAssignmentFiles({
    required String enumeratorId,
    required String assignmentId,
    required List<({String filename, Uint8List bytes})> files,
  }) {
    // Upload path keeps using Google Drive. If a future story needs FTP
    // uploads, route the EnqueueAssignmentUseCase through a separate
    // upload abstraction so the source/destination choices are independent.
    throw UnsupportedError(
      'FTP upload not implemented — switch to Google Drive to submit work.',
    );
  }
}

String _joinPath(String parent, String child) {
  if (parent.endsWith('/')) return '$parent$child';
  return '$parent/$child';
}

class _FtpEntry {
  _FtpEntry({
    required this.name,
    required this.size,
    required this.isDir,
  });
  final String name;
  final int size;
  final bool isDir;
}

/// Minimal FTP client — supports LIST and RETR over passive mode. Plain
/// FTP only (no TLS). Sufficient for the trusted-LAN/VPN deployments the
/// US-45 user story describes; teams pushing over the public internet
/// should still use Drive until an FTPS upgrade lands.
class _FtpClient {
  _FtpClient._(this._control);
  final Socket _control;
  final StreamController<String> _lines = StreamController.broadcast();
  late final StreamSubscription<List<int>> _sub;
  final StringBuffer _buf = StringBuffer();

  static Future<_FtpClient> connect(FtpCredentials c) async {
    final sock = await Socket.connect(
      c.host,
      c.port,
      timeout: const Duration(seconds: 15),
    );
    final client = _FtpClient._(sock);
    client._sub = sock.listen(client._onData, onError: (Object e) {
      client._lines.addError(e);
    });
    await client._readUntil(220);
    await client._command('USER ${c.user}', expect: 331);
    await client._command('PASS ${c.password}', expect: 230);
    // Binary mode — required for shapefile components and any non-text data.
    await client._command('TYPE I', expect: 200);
    return client;
  }

  Future<void> close() async {
    try {
      await _command('QUIT', expect: 221).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Best-effort; the connection might already be torn down.
    }
    await _sub.cancel();
    await _control.close();
    _control.destroy();
    await _lines.close();
  }

  void _onData(List<int> data) {
    _buf.write(utf8.decode(data, allowMalformed: true));
    while (true) {
      final s = _buf.toString();
      final nl = s.indexOf('\n');
      if (nl < 0) break;
      final line = s.substring(0, nl).trimRight();
      _buf
        ..clear()
        ..write(s.substring(nl + 1));
      _lines.add(line);
    }
  }

  Future<String> _readUntil(int code) async {
    final wanted = '$code ';
    await for (final line in _lines.stream) {
      if (line.startsWith(wanted)) return line;
      // Multi-line replies start with `code-`; keep reading.
    }
    throw const SocketException('FTP control stream closed before reply');
  }

  Future<String> _command(String cmd, {required int expect}) async {
    _control.write('$cmd\r\n');
    return _readUntil(expect);
  }

  /// Opens a passive data connection. Caller MUST close the returned
  /// socket. Returns the freshly-connected socket; FTP final reply for the
  /// data command is read by [_readTransferComplete].
  Future<Socket> _openPasv() async {
    final reply = await _command('PASV', expect: 227);
    // 227 Entering Passive Mode (h1,h2,h3,h4,p1,p2).
    final start = reply.indexOf('(');
    final end = reply.indexOf(')');
    if (start < 0 || end < 0) {
      throw const SocketException('Malformed PASV reply');
    }
    final parts = reply.substring(start + 1, end).split(',');
    if (parts.length != 6) {
      throw const SocketException('PASV reply did not yield 6 octets');
    }
    final ip = parts.sublist(0, 4).join('.');
    final port = int.parse(parts[4]) * 256 + int.parse(parts[5]);
    return Socket.connect(ip, port, timeout: const Duration(seconds: 15));
  }

  Future<void> _readTransferComplete() async {
    // 226 Transfer complete (LIST/RETR) or 150 prelude then 226.
    await for (final line in _lines.stream) {
      if (line.startsWith('226 ') || line.startsWith('250 ')) return;
      if (line.startsWith('550 ')) {
        throw SocketException('FTP transfer failed: $line');
      }
    }
  }

  Future<List<_FtpEntry>> list(String path) async {
    final data = await _openPasv();
    _control.write('LIST $path\r\n');
    // Read 150 prelude (transfer starting) before draining data socket.
    await _readUntil(150).catchError((_) => '');
    final bytes = await data.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    await data.close();
    await _readTransferComplete();
    return _parseList(utf8.decode(bytes, allowMalformed: true));
  }

  Future<Uint8List> retrieve(String path) async {
    final data = await _openPasv();
    _control.write('RETR $path\r\n');
    await _readUntil(150).catchError((_) => '');
    final bytes = await data.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    await data.close();
    await _readTransferComplete();
    return Uint8List.fromList(bytes);
  }
}

/// Parses a UNIX-style FTP LIST listing. Each line looks like:
///   drwxr-xr-x  1 owner group   4096 May 15 10:20 folder_name
///   -rw-r--r--  1 owner group  12345 May 15 10:20 file.shp
/// We tolerate Windows IIS-style listings by falling back to a name-only
/// parse — the resulting entries lose size info but still let the user
/// discover folders.
List<_FtpEntry> _parseList(String body) {
  final entries = <_FtpEntry>[];
  for (final raw in body.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('total ')) continue;
    final unix = RegExp(
      r'^([dl\-])[rwxstST\-]{9}\s+\d+\s+\S+\s+\S+\s+(\d+)\s+\S+\s+\S+\s+\S+\s+(.+)$',
    ).firstMatch(line);
    if (unix != null) {
      final type = unix.group(1)!;
      final size = int.tryParse(unix.group(2)!) ?? 0;
      final name = unix.group(3)!;
      if (name == '.' || name == '..') continue;
      entries.add(_FtpEntry(name: name, size: size, isDir: type == 'd'));
      continue;
    }
    // Windows-style: "05-15-26  10:20AM       <DIR>          name"
    final win = RegExp(
      r'^(\d{2}-\d{2}-\d{2,4})\s+\d{2}:\d{2}(?:AM|PM)\s+(<DIR>|\d+)\s+(.+)$',
    ).firstMatch(line);
    if (win != null) {
      final sizeOrDir = win.group(2)!;
      final name = win.group(3)!;
      final isDir = sizeOrDir == '<DIR>';
      final size = isDir ? 0 : int.tryParse(sizeOrDir) ?? 0;
      entries.add(_FtpEntry(name: name, size: size, isDir: isDir));
      continue;
    }
    // Unknown format — fall back to whitespace-split name.
    final tokens = line.split(RegExp(r'\s+'));
    if (tokens.isNotEmpty) {
      entries.add(_FtpEntry(name: tokens.last, size: 0, isDir: false));
    }
  }
  return entries;
}
