import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:firecheck/features/review/domain/drive_upload_state.dart';
import 'package:firecheck/features/review/presentation/drive_upload_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late AssignmentRepository repo;
  const assignmentId = 'aabbccdd-1234-5678-abcd-ef0123456789';
  const enumeratorId = 'enum-1';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AssignmentRepository(db: db);
  });

  tearDown(() async => db.close());

  Future<void> insertAssignment() async {
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
          id: assignmentId,
          enumeratorId: enumeratorId,
          campaignId: 'campaign-1',
          boundaryPolygonGeojson: '{}',
          createdAt: DateTime(2026, 5, 2),
        ));
  }

  DriveUploadNotifier notifier() =>
      DriveUploadNotifier(assignmentRepository: repo);

  group('initFromDb', () {
    test('stays Idle when no drive result stored', () async {
      await insertAssignment();
      final n = notifier();
      await n.initFromDb(assignmentId);
      expect(n.state, isA<DriveUploadIdle>());
    });

    test('transitions to Success when result already in DB', () async {
      await insertAssignment();
      final confirmedAt = DateTime(2026, 5, 2, 20, 42);
      await repo.setDriveUploadResult(
        assignmentId: assignmentId,
        driveFolderPath: 'FieldData/enum-1/2026-05-02/',
        driveFolderUrl: 'https://drive.google.com/drive/folders/abc',
        driveUploadConfirmedAt: confirmedAt,
      );

      final n = notifier();
      await n.initFromDb(assignmentId);

      final state = n.state as DriveUploadSuccess;
      expect(state.folderPath, 'FieldData/enum-1/2026-05-02/');
      expect(state.folderUrl, 'https://drive.google.com/drive/folders/abc');
      expect(state.referenceId, 'ASN-AABBCCDD');
      expect(state.confirmedAt, confirmedAt);
    });
  });

  group('applyQueueSuccess / applyQueueFailure', () {
    test('applyQueueSuccess emits Success with reference id from assignment',
        () async {
      await insertAssignment();
      final n = notifier();
      await n.initFromDb(assignmentId);

      final confirmedAt = DateTime(2026, 5, 2, 20, 42);
      n.applyQueueSuccess(
        folderPath: 'firecheck/cebu/',
        confirmedAt: confirmedAt,
      );

      final s = n.state as DriveUploadSuccess;
      expect(s.folderPath, 'firecheck/cebu/');
      expect(s.referenceId, 'ASN-AABBCCDD');
      expect(s.confirmedAt, confirmedAt);
    });

    test('applyQueueFailure emits Failure with given canRetry', () {
      final n = notifier();
      n.applyQueueFailure('boom', canRetry: false);
      final f = n.state as DriveUploadFailure;
      expect(f.message, 'boom');
      expect(f.canRetry, isFalse);
    });
  });
}
