import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';
import 'package:firecheck/core/gateway/gateway_client.dart';
import 'package:firecheck/core/gateway/gateway_map_source.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const owner = '00000000-0000-0000-0000-000000000001';
  const assignment = '00000000-0000-0000-0000-000000000002';
  const version = '00000000-0000-0000-0000-000000000003';
  const artifact = '00000000-0000-0000-0000-000000000004';
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gateway-test-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  GatewayMapSource source(Future<http.Response> Function(http.Request) send) =>
      GatewayMapSource(
          GatewayClient(
              baseUri: Uri.parse('https://files.example.com'),
              userId: () => owner,
              accessToken: () => 'app-token',
              refresh: () async {},
              client: MockClient(send)),
          temporaryDirectory: () async => dir);
  final bytes = utf8.encode('a validated map component');
  Map<String, dynamic> manifest({String? checksum}) => {
        'version': version,
        'files': [
          {
            'id': artifact,
            'name': 'buildings.shp',
            'size': bytes.length,
            'md5': checksum ?? md5.convert(bytes).toString()
          }
        ]
      };
  Map<String, dynamic> listing() => {
        'assignments': [
          {'id': assignment, 'name': 'Cebu', 'version': version}
        ],
        'next': null
      };
  test('resumes cached partial file and verifies the final checksum', () async {
    final partial = File(
        '${dir.path}/firecheck-gateway/$owner/$assignment/$version/$artifact.part');
    await partial.parent.create(recursive: true);
    await partial.writeAsBytes(bytes.sublist(0, 3));
    final s = source((r) async {
      if (r.url.path == '/v1/assignments')
        return http.Response(jsonEncode(listing()), 200);
      if (r.url.path.endsWith('/manifest'))
        return http.Response(jsonEncode(manifest()), 200);
      expect(r.headers['Range'], 'bytes=3-${bytes.length - 1}');
      return http.Response.bytes(bytes.sublist(3), 206, headers: {
        'content-range': 'bytes 3-${bytes.length - 1}/${bytes.length}'
      });
    });
    final list = await s.listAssignments();
    expect(list.single.localAssignmentId, assignment);
    expect(list.single.displayName, 'Cebu');
    final events = await s.downloadShapefiles(assignment).toList();
    expect(
        (events.last as DriveDownloadComplete).files['buildings.shp'], bytes);
  });
  test('downloads a large component in bounded ranges', () async {
    final large = List<int>.filled(4 * 1024 * 1024 + 73, 42);
    final expectedManifest = manifest();
    final fileSpec = (expectedManifest['files'] as List).single as Map<String, dynamic>;
    fileSpec['size'] = large.length;
    fileSpec['md5'] = md5.convert(large).toString();
    var requests = 0;
    final s = source((request) async {
      if (request.url.path == '/v1/assignments') return http.Response(jsonEncode(listing()), 200);
      if (request.url.path.endsWith('/manifest')) return http.Response(jsonEncode(expectedManifest), 200);
      final range = RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(request.headers['Range']!);
      expect(range, isNotNull);
      final start = int.parse(range!.group(1)!);
      final end = int.parse(range.group(2)!);
      expect(end - start + 1, lessThanOrEqualTo(4 * 1024 * 1024));
      requests++;
      return http.Response.bytes(large.sublist(start, end + 1), 206, headers: {
        'content-range': 'bytes $start-$end/${large.length}',
      });
    });
    await s.listAssignments();
    final events = await s.downloadShapefiles(assignment).toList();
    expect(requests, 2);
    expect((events.last as DriveDownloadComplete).files['buildings.shp'], large);
  });
  test('corrupted file is removed instead of imported', () async {
    final s = source((r) async {
      if (r.url.path == '/v1/assignments')
        return http.Response(jsonEncode(listing()), 200);
      if (r.url.path.endsWith('/manifest'))
        return http.Response(jsonEncode(manifest(checksum: '0' * 32)), 200);
      return http.Response.bytes(bytes, 200);
    });
    await s.listAssignments();
    await expectLater(s.downloadShapefiles(assignment).toList(),
        throwsA(isA<ValidationFailure>()));
    expect(
        await File(
                '${dir.path}/firecheck-gateway/$owner/$assignment/$version/$artifact.part')
            .exists(),
        false);
  });
}
