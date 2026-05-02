import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/enqueue_assignment_use_case.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('enqueue_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<AppDatabase> _seedDb() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
      id: 'a1', enumeratorId: 'e1', campaignId: 'c1',
      boundaryPolygonGeojson: '{}', createdAt: DateTime(2026),
    ));
    await db.into(db.features).insert(FeaturesCompanion.insert(
      id: 'f1', assignmentId: 'a1', featureType: 'building',
      geometryGeojson: '{"type":"Polygon","coordinates":[[[0,0],[1,0],[1,1],[0,1],[0,0]]]}',
      status: const Value('complete'), createdAt: DateTime(2026),
    ));
    await db.into(db.submissions).insert(SubmissionsCompanion.insert(
      id: 's1', featureId: 'f1', createdAt: DateTime(2026), updatedAt: DateTime(2026),
    ));
    await db.into(db.buildingAttributes).insert(BuildingAttributesCompanion.insert(
      submissionId: 's1',
      fireFightingFacilitiesJson: const Value('[]'),
      fireLoadJson: const Value('[]'),
      costIsExact: const Value(false),
    ));
    await db.into(db.photos).insert(PhotosCompanion.insert(
      id: 'ph1', submissionId: 's1',
      localPath: '${tempDir.path}/photo1.jpg',
      capturedAt: DateTime(2026), createdAt: DateTime(2026),
    ));
    // Create the photo file so File.length() succeeds
    await File('${tempDir.path}/photo1.jpg').writeAsBytes([0xFF, 0xD8]);
    return db;
  }

  test('enqueue creates shapefile job + photo job', () async {
    final db = await _seedDb();
    addTearDown(db.close);
    final repo = DriveUploadRepository(db);
    final exporter = ShapefileExporter(db: db, tempDirOverride: tempDir);
    final useCase = EnqueueAssignmentUseCase(
      db: db,
      repo: repo,
      exporter: exporter,
    );

    final count = await useCase.execute(assignmentId: 'a1');

    expect(count, 2); // 1 shapefile + 1 photo
    final jobs = await repo.getPendingJobs();
    expect(jobs.length, 2);
    expect(jobs.any((j) => j.fileType == DriveFileType.shapefile), isTrue);
    expect(jobs.any((j) => j.fileType == DriveFileType.photo), isTrue);
  });

  test('enqueue is idempotent — second call adds no new jobs', () async {
    final db = await _seedDb();
    addTearDown(db.close);
    final repo = DriveUploadRepository(db);
    final exporter = ShapefileExporter(db: db, tempDirOverride: tempDir);
    final useCase = EnqueueAssignmentUseCase(db: db, repo: repo, exporter: exporter);

    await useCase.execute(assignmentId: 'a1');
    final secondCount = await useCase.execute(assignmentId: 'a1');

    expect(secondCount, 0);
    final jobs = await db.select(db.driveUploadJobs).get();
    expect(jobs.length, 2); // still 2, no duplicates
  });
}
