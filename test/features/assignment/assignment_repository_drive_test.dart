import 'package:drift/drift.dart' hide isNull, isNotNull;
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

  test('confirmation blocks duplicates and new survey edits enable upload',
      () async {
    await insertAssignment();
    expect(await repo.hasChangesToUpload(assignmentId), isTrue);
    await db.into(db.features).insert(FeaturesCompanion.insert(
          id: 'feature',
          assignmentId: assignmentId,
          featureType: 'building',
          geometryGeojson: '{}',
          createdAt: DateTime(2026, 5, 1),
        ));
    await db.into(db.submissions).insert(SubmissionsCompanion.insert(
          id: 'survey',
          featureId: 'feature',
          createdAt: DateTime(2026, 5, 1),
          updatedAt: DateTime(2026, 5, 1),
        ));
    await repo.setDriveUploadResult(
      assignmentId: assignmentId,
      driveFolderPath: 'output',
      driveFolderUrl: '',
      driveUploadConfirmedAt: DateTime(2026, 5, 2),
    );
    // A new repository represents reopening the screen/app.
    expect(await AssignmentRepository(db: db).hasChangesToUpload(assignmentId),
        isFalse);
    expect(await repo.watchHasChangesToUpload(assignmentId).first, isFalse);
    await (db.update(db.submissions)..where((s) => s.id.equals('survey')))
        .write(
      SubmissionsCompanion(updatedAt: Value(DateTime(2026, 5, 3))),
    );
    expect(await repo.hasChangesToUpload(assignmentId), isTrue);
  });

  test('changes on another assignment do not enable a confirmed upload',
      () async {
    await insertAssignment();
    await repo.setDriveUploadResult(
      assignmentId: assignmentId,
      driveFolderPath: 'output',
      driveFolderUrl: '',
      driveUploadConfirmedAt: DateTime(2026, 5, 2),
    );
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
          id: 'other',
          enumeratorId: 'enumerator-1',
          campaignId: 'campaign-1',
          boundaryPolygonGeojson: '{}',
          createdAt: DateTime(2026, 5, 3),
        ));
    await db.into(db.features).insert(FeaturesCompanion.insert(
          id: 'other-feature',
          assignmentId: 'other',
          featureType: 'building',
          geometryGeojson: '{}',
          createdAt: DateTime(2026, 5, 3),
        ));
    expect(await repo.hasChangesToUpload(assignmentId), isFalse);
    expect(await repo.hasChangesToUpload('other'), isTrue);
  });

  test('discarded geometry does not keep a shared map uploadable', () async {
    await insertAssignment();
    repo = AssignmentRepository(db: db, userId: 'enumerator-1');
    await db.into(db.sharedMapCursors).insert(SharedMapCursorsCompanion.insert(
        accountId: 'enumerator-1', assignmentId: assignmentId));
    await db.into(db.features).insert(FeaturesCompanion.insert(
        id: 'feature',
        assignmentId: assignmentId,
        featureType: 'building',
        geometryGeojson: '{}',
        createdAt: DateTime(2026)));
    await db.into(db.featureGeometryRevisions).insert(
        FeatureGeometryRevisionsCompanion.insert(
            id: 'revision',
            featureId: 'feature',
            prevGeojson: '{}',
            newGeojson: '{}',
            editedBy: 'enumerator-1',
            editedAt: DateTime(2026),
            createdAt: DateTime(2026),
            syncStatus: const Value('failed')));
    expect(await repo.hasChangesToUpload(assignmentId), isTrue);
    await (db.update(db.featureGeometryRevisions)
          ..where((r) => r.id.equals('revision')))
        .write(const FeatureGeometryRevisionsCompanion(
            syncStatus: Value('discarded')));
    expect(await repo.hasChangesToUpload(assignmentId), isFalse);
    expect(await repo.watchHasChangesToUpload(assignmentId).first, isFalse);
  });

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
      expect(
          result.folderUrl, 'https://drive.google.com/drive/folders/fake-id');
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
      expect(
          result!.folderUrl, 'https://drive.google.com/drive/folders/new-id');
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
