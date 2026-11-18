import 'dart:async';
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
      if (r.url.path == '/v1/assignments') {
        return http.Response(jsonEncode(listing()), 200);
      }
      if (r.url.path.endsWith('/manifest')) {
        return http.Response(jsonEncode(manifest()), 200);
      }
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
    final fileSpec =
        (expectedManifest['files'] as List).single as Map<String, dynamic>;
    fileSpec['size'] = large.length;
    fileSpec['md5'] = md5.convert(large).toString();
    var requests = 0;
    final s = source((request) async {
      if (request.url.path == '/v1/assignments') {
        return http.Response(jsonEncode(listing()), 200);
      }
      if (request.url.path.endsWith('/manifest')) {
        return http.Response(jsonEncode(expectedManifest), 200);
      }
      final range =
          RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(request.headers['Range']!);
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
    expect(
      (events.last as DriveDownloadComplete).files['buildings.shp'],
      large,
    );
  });
  test('corrupted file is removed instead of imported', () async {
    final s = source((r) async {
      if (r.url.path == '/v1/assignments') {
        return http.Response(jsonEncode(listing()), 200);
      }
      if (r.url.path.endsWith('/manifest')) {
        return http.Response(jsonEncode(manifest(checksum: '0' * 32)), 200);
      }
      return http.Response.bytes(bytes, 200);
    });
    await s.listAssignments();
    final events = <DriveDownloadEvent>[];
    await expectLater(
        s.downloadShapefiles(assignment).map((e) {
          events.add(e);
          return e;
        }).toList(),
        throwsA(isA<ValidationFailure>()));
    expect(events.whereType<DriveDownloadComplete>(), isEmpty);
    expect(events.whereType<DriveDownloadProgress>().last.verifying, true);
    expect(
        await File(
                '${dir.path}/firecheck-gateway/$owner/$assignment/$version/$artifact.part')
            .exists(),
        false);
  });
  test('persists and exposes one range before requesting the next', () async {
    final large = List<int>.filled(4 * 1024 * 1024 + 3, 42);
    final m = manifest();
    final spec = (m['files'] as List).single as Map<String, dynamic>;
    spec['size'] = large.length;
    spec['md5'] = md5.convert(large).toString();
    final nextRequested = Completer<String>();
    final releaseNext = Completer<void>();
    final firstProgress = Completer<String>();
    final s = source((r) async {
      if (r.url.path == '/v1/assignments') {
        return http.Response(jsonEncode(listing()), 200);
      }
      if (r.url.path.endsWith('/manifest')) {
        return http.Response(jsonEncode(m), 200);
      }
      final start = int.parse(
        RegExp(r'bytes=(\d+)-').firstMatch(r.headers['Range']!)!.group(1)!,
      );
      if (start > 0) {
        nextRequested.complete('next request');
        await releaseNext.future;
      }
      final end = start == 0 ? 4 * 1024 * 1024 : large.length;
      return http.Response.bytes(
        large.sublist(start, end),
        206,
        headers: {
          'content-range': 'bytes $start-${end - 1}/${large.length}',
        },
      );
    });
    await s.listAssignments();
    final events = <DriveDownloadEvent>[];
    final subscription = s.downloadShapefiles(assignment).listen((e) {
      events.add(e);
      if (e is DriveDownloadProgress && !firstProgress.isCompleted) {
        firstProgress.complete('progress');
      }
    });
    try {
      expect(
        await Future.any([firstProgress.future, nextRequested.future]),
        'progress',
      );
      final progress = events.whereType<DriveDownloadProgress>().last;
      expect(progress.downloaded, 4 * 1024 * 1024);
      expect(progress.total, large.length);
      final partial = File(
        '${dir.path}/firecheck-gateway/$owner/$assignment/$version/$artifact.part',
      );
      expect(await partial.length(), 4 * 1024 * 1024);
      expect(events.whereType<DriveDownloadComplete>(), isEmpty);
    } finally {
      releaseNext.complete();
      await subscription.cancel();
    }
  });

  test('account relist on same source cannot adopt an active old transfer',
      () async {
    var actor = owner;
    final stream = StreamController<List<int>>();
    final listening = Completer<void>();
    stream.onListen = listening.complete;
    final s = GatewayMapSource(
      GatewayClient(
        baseUri: Uri.parse('https://files.example.com'),
        userId: () => actor,
        accessToken: () => 'token',
        refresh: () async {},
        client: MockClient.streaming((r, body) async {
          if (r.url.path == '/v1/assignments') {
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode(listing()))),
              200,
            );
          }
          if (r.url.path.endsWith('/manifest')) {
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode(manifest()))),
              200,
            );
          }
          return http.StreamedResponse(stream.stream, 200);
        }),
      ),
      temporaryDirectory: () async => dir,
    );
    await s.listAssignments();
    final completed = s.downloadShapefiles(assignment).toList();
    final failure = expectLater(completed, throwsA(isA<AuthFailure>()));
    await listening.future;
    actor = '00000000-0000-0000-0000-000000000099';
    await s.listAssignments();
    stream.add(bytes);
    await stream.close();
    await failure;
    expect(
      Directory('${dir.path}/firecheck-gateway/$actor').existsSync(),
      false,
    );
  });

  test('truncated response retains persisted bytes for a new source retry',
      () async {
    var retry = false;
    final s = source((r) async {
      if (r.url.path == '/v1/assignments') {
        return http.Response(jsonEncode(listing()), 200);
      }
      if (r.url.path.endsWith('/manifest')) {
        return http.Response(jsonEncode(manifest()), 200);
      }
      expect(r.headers['Range'], 'bytes=${retry ? 3 : 0}-${bytes.length - 1}');
      return http.Response.bytes(
        retry ? bytes.sublist(3) : bytes.sublist(0, 3),
        206,
        headers: {
          'content-range':
              'bytes ${retry ? 3 : 0}-${bytes.length - 1}/${bytes.length}',
        },
      );
    });
    await s.listAssignments();
    await expectLater(
      s.downloadShapefiles(assignment).toList(),
      throwsA(isA<NetworkFailure>()),
    );
    retry = true;
    final events = await s.downloadShapefiles(assignment).toList();
    expect(
      (events.last as DriveDownloadComplete).files['buildings.shp'],
      bytes,
    );
    expect(
      events
          .whereType<DriveDownloadProgress>()
          .every((p) => p.downloaded <= p.total),
      true,
    );
  });

  test('ignored Range resets partial bytes without accumulating twice',
      () async {
    final partial = File(
      '${dir.path}/firecheck-gateway/$owner/$assignment/$version/$artifact.part',
    );
    await partial.parent.create(recursive: true);
    await partial.writeAsBytes(bytes.sublist(0, 3));
    final s = source((r) async {
      if (r.url.path == '/v1/assignments') {
        return http.Response(jsonEncode(listing()), 200);
      }
      if (r.url.path.endsWith('/manifest')) {
        return http.Response(jsonEncode(manifest()), 200);
      }
      return http.Response.bytes(bytes, 200);
    });
    await s.listAssignments();
    final events = await s.downloadShapefiles(assignment).toList();
    expect(
      (events.last as DriveDownloadComplete).files['buildings.shp'],
      bytes,
    );
    expect(
      events
          .whereType<DriveDownloadProgress>()
          .every((p) => p.downloaded >= 0 && p.downloaded <= bytes.length),
      true,
    );
  });

  test('sidecar uses the shared resumable checksum path', () async {
    final m = manifest();
    ((m['files'] as List).single as Map<String, dynamic>)['name'] =
        'field_requirements.txt';
    final s = source((r) async {
      if (r.url.path == '/v1/assignments') {
        return http.Response(jsonEncode(listing()), 200);
      }
      if (r.url.path.endsWith('/manifest')) {
        return http.Response(jsonEncode(m), 200);
      }
      return http.Response.bytes(bytes, 200);
    });
    await s.listAssignments();
    expect(await s.fetchFieldRequirementsSidecar(assignment), bytes);
    expect(await s.fetchFormDefinitionSidecar(assignment), isNull);
  });

  test('rejects an oversized total before downloading any component', () async {
    final m = manifest();
    ((m['files'] as List).single as Map<String, dynamic>)['size'] =
        128 * 1024 * 1024 + 1;
    final s = source((r) async {
      if (r.url.path == '/v1/assignments') {
        return http.Response(jsonEncode(listing()), 200);
      }
      if (r.url.path.endsWith('/manifest')) {
        return http.Response(jsonEncode(m), 200);
      }
      fail('An oversized bundle must not request bytes');
    });
    await s.listAssignments();
    await expectLater(
      s.downloadShapefiles(assignment).toList(),
      throwsA(isA<StorageFailure>()),
    );
  });

  test(
      'cancel after persisted bytes closes HTTP body and retains resumable part',
      () async {
    final body = StreamController<List<int>>();
    final cancelled = Completer<void>();
    body.onCancel = cancelled.complete;
    final s = GatewayMapSource(
      GatewayClient(
        baseUri: Uri.parse('https://files.example.com'),
        userId: () => owner,
        accessToken: () => 'token',
        refresh: () async {},
        client: MockClient.streaming((r, _) async {
          if (r.url.path == '/v1/assignments') {
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode(listing()))),
              200,
            );
          }
          if (r.url.path.endsWith('/manifest')) {
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode(manifest()))),
              200,
            );
          }
          return http.StreamedResponse(body.stream, 200);
        }),
      ),
      temporaryDirectory: () async => dir,
    );
    await s.listAssignments();
    final iterator = StreamIterator(s.downloadShapefiles(assignment));
    body.add(bytes.sublist(0, 3));
    expect(await iterator.moveNext(), true);
    expect((iterator.current as DriveDownloadProgress).downloaded, 3);
    await iterator.cancel();
    await cancelled.future;
    final part = File(
      '${dir.path}/firecheck-gateway/$owner/$assignment/$version/$artifact.part',
    );
    expect(await part.readAsBytes(), bytes.sublist(0, 3));
    await body.close();
  });

  test('stale manifest body is rejected after same-source account relist',
      () async {
    var actor = owner;
    var manifestCalls = 0;
    final oldBody = StreamController<List<int>>();
    final reading = Completer<void>();
    oldBody.onListen = reading.complete;
    final s = GatewayMapSource(
      GatewayClient(
        baseUri: Uri.parse('https://files.example.com'),
        userId: () => actor,
        accessToken: () => 'token',
        refresh: () async {},
        client: MockClient.streaming((r, _) async {
          if (r.url.path == '/v1/assignments') {
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode(listing()))),
              200,
            );
          }
          manifestCalls++;
          if (manifestCalls == 1) {
            return http.StreamedResponse(oldBody.stream, 200);
          }
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode(manifest()))),
            200,
          );
        }),
      ),
      temporaryDirectory: () async => dir,
    );
    await s.listAssignments();
    final stale =
        expectLater(s.getTotalSize(assignment), throwsA(isA<AuthFailure>()));
    await reading.future;
    actor = '00000000-0000-0000-0000-000000000099';
    await s.listAssignments();
    oldBody.add(utf8.encode(jsonEncode(manifest())));
    await oldBody.close();
    await stale;
    expect(await s.getTotalSize(assignment), bytes.length);
    expect(
      manifestCalls,
      2,
      reason: 'A manifest must not populate the B cache',
    );
  });

  test('truncated reset response stops instead of retrying the same prefix',
      () async {
    var requests = 0;
    final s = source((r) async {
      if (r.url.path == '/v1/assignments') {
        return http.Response(jsonEncode(listing()), 200);
      }
      if (r.url.path.endsWith('/manifest')) {
        return http.Response(jsonEncode(manifest()), 200);
      }
      requests++;
      if (requests > 1) throw StateError('Repeated truncated reset');
      return http.Response.bytes(bytes.sublist(0, 3), 200);
    });
    await s.listAssignments();
    await expectLater(
      s.downloadShapefiles(assignment).toList(),
      throwsA(isA<NetworkFailure>()),
    );
    expect(requests, 1);
  });
  test('verified prior component and reset resumed component are counted once',
      () async {
    const priorId = '00000000-0000-0000-0000-000000000005';
    final m = manifest();
    m['files'] = <Map<String, dynamic>>[
      {
        'id': priorId,
        'name': 'boundary.shp',
        'size': 2,
        'md5': md5.convert([1, 2]).toString(),
      },
      ...(m['files'] as List).cast<Map<String, dynamic>>(),
    ];
    final base = '${dir.path}/firecheck-gateway/$owner/$assignment/$version';
    await Directory(base).create(recursive: true);
    await File('$base/$priorId.part').writeAsBytes([1, 2]);
    await File('$base/$artifact.part').writeAsBytes(bytes.sublist(0, 3));
    final s = source((r) async {
      if (r.url.path == '/v1/assignments') {
        return http.Response(jsonEncode(listing()), 200);
      }
      if (r.url.path.endsWith('/manifest')) {
        return http.Response(jsonEncode(m), 200);
      }
      expect(r.url.path.endsWith('/$artifact'), true);
      expect(r.headers['Range'], 'bytes=3-${bytes.length - 1}');
      return http.Response.bytes(bytes, 200);
    });
    await s.listAssignments();
    final events = await s.downloadShapefiles(assignment).toList();
    final progress = events.whereType<DriveDownloadProgress>().toList();
    expect(progress.map((p) => p.downloaded), [2, 5, 27]);
    expect(progress.map((p) => p.verifying), [false, false, true]);
    expect(progress.map((p) => p.total), everyElement(27));
    expect(
      (events.last as DriveDownloadComplete).files.keys,
      unorderedEquals(['boundary.shp', 'buildings.shp']),
    );
  });
  test('invalid resume response cancels an open body before reporting failure',
      () async {
    final body = StreamController<List<int>>();
    final cancelled = Completer<void>();
    final cancellationObserved = Completer<bool>();
    body
      ..onCancel = cancelled.complete
      ..onListen = () => scheduleMicrotask(() {
            cancellationObserved.complete(cancelled.isCompleted);
          });
    final s = GatewayMapSource(
      GatewayClient(
        baseUri: Uri.parse('https://files.example.com'),
        userId: () => owner,
        accessToken: () => 'token',
        refresh: () async {},
        client: MockClient.streaming((r, _) async {
          if (r.url.path == '/v1/assignments') {
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode(listing()))),
              200,
            );
          }
          if (r.url.path.endsWith('/manifest')) {
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode(manifest()))),
              200,
            );
          }
          return http.StreamedResponse(
            body.stream,
            206,
            headers: {'content-range': 'bytes 4-5/99'},
          );
        }),
      ),
      temporaryDirectory: () async => dir,
    );
    await s.listAssignments();
    final failure = expectLater(
      s.downloadShapefiles(assignment).toList(),
      throwsA(isA<NetworkFailure>()),
    );
    final didCancel = await cancellationObserved.future;
    if (didCancel) {
      await failure; // Server has not sent bytes or closed the body.
      await body.close();
    } else {
      await body.close(); // Release the old drain path so RED never hangs.
      await failure;
    }
    expect(didCancel, true);
    expect(
      Directory('${dir.path}/firecheck-gateway/$owner/$assignment/$version')
          .listSync(),
      isEmpty,
    );
  });
}
