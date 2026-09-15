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
  const owner = '00000000-0000-0000-0000-000000000001';
  const other = '00000000-0000-0000-0000-000000000002';
  const batch = '00000000-0000-0000-0000-000000000003';
  const assignment = '00000000-0000-0000-0000-000000000004';
  const job = '00000000-0000-0000-0000-000000000005';
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DriveUploadRepository(db);
    dir = await Directory.systemTemp.createTemp('gateway-upload-');
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });
  Future<void> seed({String? who = owner, String? batchId = batch}) async {
    final file = File('${dir.path}/buildings.shp');
    await file.writeAsString('shape');
    await repo.insertJob(
        id: job,
        assignmentId: assignment,
        filePath: file.path,
        fileType: 'shapefile',
        fileName: 'buildings.shp',
        fileSizeBytes: 5,
        capturedAt: DateTime.now(),
        ownerId: who,
        batchId: batchId);
  }

  GatewayUploadRunner runner(
          Future<http.Response> Function(http.Request) send) =>
      GatewayUploadRunner(
          repo: repo,
          client: GatewayClient(
              baseUri: Uri.parse('https://files.example.com'),
              userId: () => owner,
              accessToken: () => 'app-token',
              refresh: () async {},
              client: MockClient(send)));
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
  });
}
