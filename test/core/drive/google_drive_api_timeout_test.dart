import 'dart:async';

import 'package:firecheck/core/drive/google_drive_api.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as gdrive;
import 'package:mocktail/mocktail.dart';

class _HangingTokenSource implements GoogleTokenSource {
  int tokenRequests = 0;

  @override
  Future<String> getAccessToken() {
    tokenRequests += 1;
    return Completer<String>().future;
  }

  @override
  Future<String> getEnumeratorId() async => 'enumerator';

  @override
  Future<bool> isSignedIn() async => true;
}

class _FakeTokenSource implements GoogleTokenSource {
  @override
  Future<String> getAccessToken() async => 'token';

  @override
  Future<String> getEnumeratorId() async => 'enumerator';

  @override
  Future<bool> isSignedIn() async => true;
}

class _MockDriveApi extends Mock implements gdrive.DriveApi {}

class _MockFilesResource extends Mock implements gdrive.FilesResource {}

void main() {
  setUpAll(() {
    registerFallbackValue(gdrive.DownloadOptions.fullMedia);
  });

  test(
      'assignment listing has a bounded authentication timeout and retries fresh',
      () async {
    final source = _HangingTokenSource();
    final api = GoogleDriveApi(
      googleAuthRepo: source,
      requestTimeout: const Duration(milliseconds: 10),
    );

    await expectLater(api.listAssignments(), throwsA(isA<NetworkFailure>()));
    await expectLater(api.listAssignments(), throwsA(isA<NetworkFailure>()));
    expect(source.tokenRequests, 2);
  });

  test('stalled Drive list call times out and retry starts a fresh call',
      () async {
    final api = _MockDriveApi();
    final files = _MockFilesResource();
    var listCalls = 0;
    when(() => api.files).thenReturn(files);
    when(
      () => files.list(
        q: any(named: 'q'),
        spaces: any(named: 'spaces'),
        $fields: any(named: r'$fields'),
      ),
    ).thenAnswer((_) {
      listCalls += 1;
      return Completer<gdrive.FileList>().future;
    });

    final drive = GoogleDriveApi(
      googleAuthRepo: _FakeTokenSource(),
      apiOverride: api,
      requestTimeout: const Duration(milliseconds: 10),
    );

    await expectLater(drive.listAssignments(), throwsA(isA<NetworkFailure>()));
    await expectLater(drive.listAssignments(), throwsA(isA<NetworkFailure>()));
    expect(listCalls, 2);
  });

  test('map media stream fails after bounded inactivity', () async {
    final api = _MockDriveApi();
    final files = _MockFilesResource();
    final stalled = StreamController<List<int>>();
    addTearDown(stalled.close);
    when(() => api.files).thenReturn(files);

    var listCall = 0;
    when(
      () => files.list(
        q: any(named: 'q'),
        spaces: any(named: 'spaces'),
        $fields: any(named: r'$fields'),
      ),
    ).thenAnswer((_) async {
      listCall += 1;
      return switch (listCall) {
        1 => gdrive.FileList()..files = [gdrive.File()..id = 'firecheck'],
        2 => gdrive.FileList()..files = [gdrive.File()..id = 'input'],
        3 => gdrive.FileList()
          ..files = [
            gdrive.File()
              ..id = 'assignment-folder'
              ..name = 'cebu'
              ..modifiedTime = DateTime.utc(2026),
          ],
        _ => gdrive.FileList()
          ..files = [
            gdrive.File()
              ..id = 'buildings-shp'
              ..name = 'buildings.shp'
              ..size = '100',
          ],
      };
    });
    when(
      () => files.get(
        any(),
        downloadOptions: any(named: 'downloadOptions'),
      ),
    ).thenAnswer((_) async => gdrive.Media(stalled.stream, 100));

    final drive = GoogleDriveApi(
      googleAuthRepo: _FakeTokenSource(),
      apiOverride: api,
      requestTimeout: const Duration(milliseconds: 20),
      inactivityTimeout: const Duration(milliseconds: 20),
    );
    await drive.listAssignments();

    await expectLater(
      drive.downloadShapefiles('cebu').toList(),
      throwsA(isA<NetworkFailure>()),
    );
  });
}
