import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late AssignmentRepository repo;
  const assignmentId = 'aabbccdd-1234-5678-abcd-ef0123456789';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AssignmentRepository(db: db);
  });

  tearDown(() async => db.close());

  Future<void> insertAssignment() async {
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
          id: assignmentId,
          enumeratorId: 'enumerator-1',
          campaignId: 'campaign-1',
          boundaryPolygonGeojson: '{}',
          createdAt: DateTime(2026, 5, 2),
        ));
  }

  group('getDriveUploadResult', () {
    test('returns null when columns are unset', () async {
      await insertAssignment();
      expect(await repo.getDriveUploadResult(assignmentId), isNull);
    });

    test('returns null when assignment does not exist', () async {
      expect(await repo.getDriveUploadResult('nonexistent'), isNull);
    });
  });

  group('setDriveUploadResult + getDriveUploadResult', () {
    test('round-trips all three values', () async {
      await insertAssignment();
      final confirmedAt = DateTime(2026, 5, 2, 20, 42);

      await repo.setDriveUploadResult(
        assignmentId: assignmentId,
        driveFolderPath: 'FieldData/enumerator-1/2026-05-02/',
        driveFolderUrl: 'https://drive.google.com/drive/folders/fake-id',
        driveUploadConfirmedAt: confirmedAt,
      );

      final result = await repo.getDriveUploadResult(assignmentId);
      expect(result, isNotNull);
      expect(result!.folderPath, 'FieldData/enumerator-1/2026-05-02/');
      expect(result.folderUrl, 'https://drive.google.com/drive/folders/fake-id');
      expect(result.confirmedAt, confirmedAt);
    });

    test('subsequent call overwrites previous values', () async {
      await insertAssignment();
      await repo.setDriveUploadResult(
        assignmentId: assignmentId,
        driveFolderPath: 'FieldData/enumerator-1/2026-05-01/',
        driveFolderUrl: 'https://drive.google.com/drive/folders/old-id',
        driveUploadConfirmedAt: DateTime(2026, 5, 1),
      );
      await repo.setDriveUploadResult(
        assignmentId: assignmentId,
        driveFolderPath: 'FieldData/enumerator-1/2026-05-02/',
        driveFolderUrl: 'https://drive.google.com/drive/folders/new-id',
        driveUploadConfirmedAt: DateTime(2026, 5, 2),
      );

      final result = await repo.getDriveUploadResult(assignmentId);
      expect(result!.folderUrl, 'https://drive.google.com/drive/folders/new-id');
    });

    test('throws StateError when assignment does not exist', () async {
      await expectLater(
        () => repo.setDriveUploadResult(
          assignmentId: 'nonexistent',
          driveFolderPath: 'FieldData/x/2026-05-02/',
          driveFolderUrl: 'https://drive.google.com/drive/folders/x',
          driveUploadConfirmedAt: DateTime(2026, 5, 2),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
