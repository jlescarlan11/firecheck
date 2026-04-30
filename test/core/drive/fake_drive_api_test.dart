// test/core/drive/fake_drive_api_test.dart
import 'dart:typed_data';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';
import 'package:firecheck/core/drive/fake_drive_api.dart';
import 'package:flutter_test/flutter_test.dart';

const _brgy001 = DriveAssignment(
  assignmentId: 'brgy-001',
  inputZipFileId: 'file-1',
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

  test('getInputZipSize returns configured size', () async {
    final api = FakeDriveApi(assignments: [_brgy001], zipSize: 2048);
    expect(await api.getInputZipSize('brgy-001'), 2048);
  });

  test('downloadInputZip yields single complete event', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final api = FakeDriveApi(assignments: [_brgy001], downloadComplete: bytes);
    final events = await api.downloadInputZip('brgy-001').toList();
    expect(events, hasLength(1));
    expect((events.first as DriveDownloadComplete).bytes, bytes);
  });

  test('downloadInputZip yields custom event list', () async {
    final api = FakeDriveApi(
      assignments: [_brgy001],
      downloadEvents: [
        const DriveDownloadProgress(downloaded: 512, total: 1024),
        DriveDownloadComplete(Uint8List(0)),
      ],
    );
    final events = await api.downloadInputZip('brgy-001').toList();
    expect(events.first, isA<DriveDownloadProgress>());
    expect(events.last, isA<DriveDownloadComplete>());
  });

  test('downloadInputZip throws when downloadError configured', () async {
    final api = FakeDriveApi(
      assignments: [_brgy001],
      downloadError: Exception('timeout'),
    );
    expect(api.downloadInputZip('brgy-001').first, throwsException);
  });
}
