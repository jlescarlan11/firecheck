import 'dart:typed_data';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = DriveAssignment(
    assignmentId: 'brgy-001',
    inputZipModifiedTime: '2026-04-28T10:00:00Z',
    driveFolderId: 'folder-abc',
  );

  group('DriveAssignment', () {
    test('alreadyDownloaded defaults to false', () {
      expect(base.alreadyDownloaded, isFalse);
    });

    test('copyWith sets alreadyDownloaded, preserves other fields', () {
      final updated = base.copyWith(alreadyDownloaded: true);
      expect(updated.alreadyDownloaded, isTrue);
      expect(updated.assignmentId, 'brgy-001');
      expect(updated.inputZipModifiedTime, '2026-04-28T10:00:00Z');
    });

    test('equality: same fields are equal', () {
      const other = DriveAssignment(
        assignmentId: 'brgy-001',
        inputZipModifiedTime: '2026-04-28T10:00:00Z',
        driveFolderId: 'folder-abc',
      );
      expect(base, equals(other));
    });

    test('equality: different alreadyDownloaded are not equal', () {
      final downloaded = base.copyWith(alreadyDownloaded: true);
      expect(base, isNot(equals(downloaded)));
    });
  });

  group('DriveDownloadEvent', () {
    test('DriveDownloadProgress exposes downloaded + total', () {
      const e = DriveDownloadProgress(downloaded: 512, total: 1024);
      expect(e.downloaded, 512);
      expect(e.total, 1024);
    });

    test('DriveDownloadComplete exposes files map', () {
      final e = DriveDownloadComplete({'boundary.shp': Uint8List(8)});
      expect(e.files['boundary.shp']!.length, 8);
    });
  });
}
