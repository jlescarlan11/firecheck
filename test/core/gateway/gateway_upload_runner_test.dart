import 'package:firecheck/core/drive/upload_transfer_progress.dart';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/gateway/gateway_client.dart';
import 'package:firecheck/core/gateway/gateway_upload_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late AppDatabase db;
  late DriveUploadRepository repo;
  late Directory dir;
  late UploadTransferTracker progress;
  const owner = '00000000-0000-0000-0000-000000000001';
  const other = '00000000-0000-0000-0000-000000000002';
  const batch = '00000000-0000-0000-0000-000000000003';
  const assignment = '00000000-0000-0000-0000-000000000004';
  const job = '00000000-0000-0000-0000-000000000005';
  setUp(() async {
    progress = UploadTransferTracker();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DriveUploadRepository(db);
    dir = await Directory.systemTemp.createTemp('gateway-upload-');
  });
  tearDown(() async {
    progress.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });
  Future<void> seed(
      {String? who = owner, String? batchId = batch, int size = 5}) async {
    final file = File('${dir.path}/buildings.shp');
    if (size == 5) {
      await file.writeAsString('shape');
    } else {
      await file.writeAsBytes(List.filled(size, 1));
    }
    await repo.insertJob(
        id: job,
        assignmentId: assignment,
        filePath: file.path,
        fileType: 'shapefile',
        fileName: 'buildings.shp',
        fileSizeBytes: size,
        capturedAt: DateTime.now(),
        ownerId: who,
        batchId: batchId);
  }

  GatewayUploadRunner runner(
          Future<http.Response> Function(http.Request) send) =>
      GatewayUploadRunner(
          repo: repo,
          progress: progress,
          client: GatewayClient(
              baseUri: Uri.parse('https://files.example.com'),
              userId: () => owner,
              accessToken: () => 'app-token',
              refresh: () async {},
              client: MockClient(send)));
  for (final failSecondChunk in [false, true]) {
    test('progress follows acknowledged chunks, failure: $failSecondChunk',
        () async {
      const size = 1024 * 1024;
      await seed(size: size);
      var acknowledged = 0;
      final observed = <int>[];
      progress.addListener((items) {
        if (items[job] != null) observed.add(items[job]!.percent);
      });
      await runner((request) async {
        if (request.url.path.endsWith('/uploads')) {
          return http.Response('{"complete":false}', 200);
        }
        if (request.url.path.endsWith('/chunks')) {
          // MockClient has already consumed the whole request body here.
          // That must NOT advance the displayed percentage.
          expect(progress.state[job]!.sent, acknowledged);
          expect(request.bodyBytes.length, 256 * 1024);
          expect(request.headers['Upload-Offset'], '$acknowledged');
          if (failSecondChunk && acknowledged > 0) {
            return http.Response('{}', 503);
          }
          acknowledged += request.bodyBytes.length;
          return http.Response(
              jsonEncode({
                'offset': acknowledged,
                'complete': acknowledged == size,
              }),
              200);
        }
        if (request.url.path.endsWith('/complete')) {
          expect(acknowledged, size);
          return http.Response('{"complete":true}', 200);
        }
        return http.Response('{"offset":0,"complete":false}', 200);
      }).drain();
      if (failSecondChunk) {
        expect(progress.state[job]!.percent, 25);
        expect(progress.state[job]!.phase, TransferPhase.failed);
      } else {
        expect(observed, containsAllInOrder([0, 25, 50, 75, 99, 100]));
      }
    });
  }
  test('does not submit another account pending exports', () async {
    await seed(who: other);
    var requests = 0;
    await runner((_) async {
      requests++;
      return http.Response('{}', 200);
    }).drain();
    expect(requests, 0);
    expect(
        (await repo.getJobsForAssignment(assignment)).single.status, 'pending');
  });
  test('legacy queue without account binding is not adopted', () async {
    await seed(who: null, batchId: null);
    var requests = 0;
    await runner((_) async {
      requests++;
      return http.Response('{}', 200);
    }).drain();
    expect(requests, 0);
    expect((await repo.getJobsForAssignment(assignment)).single.status, 'dead');
  });
  test('marks local files complete only after server completion receipt',
      () async {
    await seed();
    final calls = <String>[];
    final r = runner((req) async {
      calls.add('${req.method} ${req.url.path}');
      if (req.url.path.endsWith('/uploads')) {
        final body = jsonDecode(req.body) as Map;
        expect(body['id'], batch);
        expect(body['files'][0]['name'], 'buildings.shp');
        return http.Response('{"complete":false}', 200);
      }
      if (req.url.path.endsWith('/chunks')) {
        expect(req.headers['Upload-Offset'], '0');
        expect(req.body, 'shape');
        return http.Response('{"offset":5,"complete":true}', 200);
      }
      if (req.url.path.endsWith('/complete')) {
        expect(progress.state[job]!.percent, 99);
        expect(progress.state[job]!.phase, TransferPhase.confirming);
        expect((await repo.getJobsForAssignment(assignment)).single.status,
            'uploading');
        return http.Response('{"complete":true}', 200);
      }
      return http.Response('{"offset":0,"complete":false}', 200);
    });
    await r.drain();
    expect((await repo.getJobsForAssignment(assignment)).single.status,
        'completed');
    expect(calls.last, 'POST /v1/uploads/$batch/complete');
    expect(progress.state[job]!.percent, 100);
    expect(progress.state[job]!.phase, TransferPhase.completed);
  });
}
