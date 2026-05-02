// test/core/drive/fake_drive_api_test.dart
import 'dart:typed_data';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';
import 'package:firecheck/core/drive/fake_drive_api.dart';
import 'package:flutter_test/flutter_test.dart';

const _brgy001 = DriveAssignment(
  assignmentId: 'brgy-001',
  inputZipModifiedTime: '2026-04-28T10:00:00Z',
  driveFolderId: 'folder-1',
);

void main() {
  test('listAssignments returns configured list', () async {
    final api = FakeDriveApi(assignments: [_brgy001]);
    expect(await api.listAssignments(), hasLength(1));
  });

  test('listAssignments throws when listError configured', () async {
    final api = FakeDriveApi(listError: Exception('network'));
    expect(api.listAssignments(), throwsException);
  });

  test('getTotalSize returns configured size', () async {
    final api = FakeDriveApi(assignments: [_brgy001], totalSize: 2048);
    expect(await api.getTotalSize('brgy-001'), 2048);
  });

  test('downloadShapefiles yields single complete event with files and md5s',
      () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final api = FakeDriveApi(
      assignments: [_brgy001],
      downloadComplete: {'boundary.shp': bytes},
      expectedMd5s: {'boundary.shp': 'deadbeef'},
    );
    final events = await api.downloadShapefiles('brgy-001').toList();
    expect(events, hasLength(1));
    final complete = events.first as DriveDownloadComplete;
    expect(complete.files['boundary.shp'], bytes);
    expect(complete.expectedMd5s['boundary.shp'], 'deadbeef');
  });

  test('downloadShapefiles yields custom event list', () async {
    final api = FakeDriveApi(
      assignments: [_brgy001],
      downloadEvents: [
        const DriveDownloadProgress(downloaded: 512, total: 1024),
        DriveDownloadComplete({'boundary.shp': Uint8List(0)}, {}),
      ],
    );
    final events = await api.downloadShapefiles('brgy-001').toList();
    expect(events.first, isA<DriveDownloadProgress>());
    expect(events.last, isA<DriveDownloadComplete>());
  });

  test('downloadShapefiles emits error when downloadError configured',
      () async {
    final api = FakeDriveApi(
      assignments: [_brgy001],
      downloadError: Exception('timeout'),
    );
    expect(
      api.downloadShapefiles('brgy-001'),
      emitsError(isA<Exception>()),
    );
  });
}
