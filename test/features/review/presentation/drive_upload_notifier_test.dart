import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/fake_drive_api.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:firecheck/features/review/domain/drive_upload_state.dart';
import 'package:firecheck/features/review/presentation/drive_upload_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late AssignmentRepository repo;
  const assignmentId = 'aabbccdd-1234-5678-abcd-ef0123456789';
  const enumeratorId = 'enum-1';
  final emptyFiles = <({String filename, Uint8List bytes})>[];

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AssignmentRepository(db: db);
  });

  tearDown(() async => db.close());

  Future<void> _insertAssignment() async {
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
      id: assignmentId,
      enumeratorId: enumeratorId,
      campaignId: 'campaign-1',
      boundaryPolygonGeojson: '{}',
      createdAt: DateTime(2026, 5, 2),
    ));
  }

  DriveUploadNotifier _notifier({FakeDriveApi? driveApi}) =>
      DriveUploadNotifier(
        driveApi: driveApi ?? FakeDriveApi(),
        assignmentRepository: repo,
      );

  group('initFromDb', () {
    test('stays Idle when no drive result stored', () async {
      await _insertAssignment();
      final n = _notifier();
      await n.initFromDb(assignmentId, enumeratorId);
      expect(n.state, isA<DriveUploadIdle>());
    });

    test('transitions to Success when result already in DB', () async {
      await _insertAssignment();
      final confirmedAt = DateTime(2026, 5, 2, 20, 42);
      await repo.setDriveUploadResult(
        assignmentId: assignmentId,
        driveFolderPath: 'FieldData/enum-1/2026-05-02/',
        driveFolderUrl: 'https://drive.google.com/drive/folders/abc',
        driveUploadConfirmedAt: confirmedAt,
      );

      final n = _notifier();
      await n.initFromDb(assignmentId, enumeratorId);

      final state = n.state as DriveUploadSuccess;
      expect(state.folderPath, 'FieldData/enum-1/2026-05-02/');
      expect(state.folderUrl, 'https://drive.google.com/drive/folders/abc');
      expect(state.referenceId, 'ASN-AABBCCDD');
      expect(state.confirmedAt, confirmedAt);
    });
  });

  group('startUpload', () {
    test('happy path: transitions Idle → InProgress → Success and writes to DB',
        () async {
      await _insertAssignment();
      final n = _notifier(
        driveApi: FakeDriveApi(
          uploadResult: (
            folderPath: 'FieldData/enum-1/2026-05-02/',
            folderUrl: 'https://drive.google.com/drive/folders/abc',
          ),
        ),
      );
      await n.initFromDb(assignmentId, enumeratorId);

      final states = <DriveUploadState>[];
      n.addListener(states.add, fireImmediately: false);
      await n.startUpload(emptyFiles);

      expect(states.first, isA<DriveUploadInProgress>());
      expect(states.last, isA<DriveUploadSuccess>());

      final dbResult = await repo.getDriveUploadResult(assignmentId);
      expect(dbResult, isNotNull);
      expect(dbResult!.folderPath, 'FieldData/enum-1/2026-05-02/');
    });

    test('network error → Failure with canRetry:true', () async {
      await _insertAssignment();
      final n = _notifier(
        driveApi: FakeDriveApi(uploadError: Exception('Network error')),
      );
      await n.initFromDb(assignmentId, enumeratorId);
      await n.startUpload(emptyFiles);

      final state = n.state as DriveUploadFailure;
      expect(state.canRetry, isTrue);
    });

    test('AuthFailure → Failure with canRetry:false', () async {
      await _insertAssignment();
      final n = _notifier(
        driveApi: FakeDriveApi(
            uploadError: const AuthFailure('Not signed in')),
      );
      await n.initFromDb(assignmentId, enumeratorId);
      await n.startUpload(emptyFiles);

      final state = n.state as DriveUploadFailure;
      expect(state.canRetry, isFalse);
    });
  });

  group('retry', () {
    test('Failure → Idle → Success after retry', () async {
      await _insertAssignment();
      final n = _notifier(
        driveApi: FakeDriveApi(
          uploadResult: (
            folderPath: 'FieldData/enum-1/2026-05-02/',
            folderUrl: 'https://drive.google.com/drive/folders/abc',
          ),
        ),
      );
      await n.initFromDb(assignmentId, enumeratorId);
      n.debugSetState(
          const DriveUploadFailure(message: 'err', canRetry: true));
      await n.retry(emptyFiles);

      expect(n.state, isA<DriveUploadSuccess>());
    });
  });
}
