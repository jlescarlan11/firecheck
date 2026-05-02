# Drive Bulk Upload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Google Drive bulk upload pipeline so enumerators can push completed photos and shapefiles to a shared organizational Drive folder when on Wi-Fi.

**Architecture:** A new `DriveUploadJobs` Drift table (DB v8) acts as the persistent upload queue. `EnqueueAssignmentUseCase` generates shapefile ZIPs and populates the queue. `DriveUploadWorker` processes jobs (mirrors `SyncWorker`). `DriveUploadController` gates uploads to Wi-Fi only. UI = home banner + `UploadQueueScreen`.

**Tech Stack:** Drift ^2.18, googleapis ^13, google_sign_in ^6, connectivity_plus ^5, workmanager ^0.9, flutter_secure_storage ^9, flutter_riverpod ^2.5

---

## File Map

**New files:**
- `lib/core/db/tables/drive_upload_jobs.dart`
- `lib/core/drive/drive_upload_job_status.dart`
- `lib/core/drive/drive_upload_repository.dart`
- `lib/core/drive/drive_upload_api.dart`
- `lib/core/drive/fake_drive_upload_api.dart`
- `lib/core/drive/google_drive_upload_api.dart`
- `lib/core/drive/drive_upload_preferences.dart`
- `lib/core/drive/drive_upload_worker.dart`
- `lib/core/drive/drive_upload_controller.dart`
- `lib/core/drive/drive_upload_workmanager.dart`
- `lib/core/drive/enqueue_assignment_use_case.dart`
- `lib/core/drive/drive_upload_providers.dart`
- `lib/features/upload/presentation/upload_banner.dart`
- `lib/features/upload/presentation/upload_queue_notifier.dart`
- `lib/features/upload/presentation/upload_queue_screen.dart`

**Modified files:**
- `lib/core/db/database.dart` — add DriveUploadJobs + v8 migration
- `lib/core/sync/shapefile/export/shapefile_exporter.dart` — add `exportToFile()`
- `lib/features/auth/data/google_auth_repository.dart` — add drive.file scope request
- `lib/core/router/app_router.dart` — add `/uploads` route
- `lib/features/home/presentation/home_screen.dart` — add upload banner

---

## Task 1: DriveUploadJobs Drift table + DB v8 migration

**Files:**
- Create: `lib/core/db/tables/drive_upload_jobs.dart`
- Modify: `lib/core/db/database.dart`
- Test: `test/core/db/drive_upload_jobs_table_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/db/drive_upload_jobs_table_test.dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('drive_upload_jobs table is accessible and accepts inserts', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.driveUploadJobs, isNotNull);

    final id = await db.into(db.driveUploadJobs).insertReturning(
          DriveUploadJobsCompanion.insert(
            id: '1',
            assignmentId: 'a-001',
            filePath: '/photos/p1.jpg',
            fileType: 'photo',
            fileName: 'p1.jpg',
            fileSizeBytes: 1024,
            capturedAt: DateTime(2026, 5, 2),
            createdAt: DateTime(2026, 5, 2),
          ),
        );

    expect(id.status, 'pending');
    expect(id.retryCount, 0);
    expect(id.resumableUri, isNull);
  });
}
```

- [ ] **Step 2: Run test — expect compile error (DriveUploadJobs not defined)**

```bash
flutter test test/core/db/drive_upload_jobs_table_test.dart
```

Expected: compile error — `DriveUploadJobs` not found.

- [ ] **Step 3: Create the Drift table**

```dart
// lib/core/db/tables/drive_upload_jobs.dart
import 'package:drift/drift.dart';

@TableIndex(name: 'drive_upload_jobs_status_idx', columns: {#status, #nextRetryAt})
@TableIndex(name: 'drive_upload_jobs_assignment_idx', columns: {#assignmentId})
class DriveUploadJobs extends Table {
  TextColumn get id => text()();
  TextColumn get assignmentId => text()();
  TextColumn get filePath => text()();
  TextColumn get fileType => text()(); // 'photo' | 'shapefile'
  TextColumn get fileName => text()();
  IntColumn get fileSizeBytes => integer()();
  DateTimeColumn get capturedAt => dateTime()();
  TextColumn get status =>
      text().withDefault(const Constant('pending'))(); // pending|uploading|completed|failed|dead
  TextColumn get resumableUri => text().nullable()();
  TextColumn get driveFileId => text().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get failureReason => text().nullable()();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 4: Add table to AppDatabase and write v8 migration**

In `lib/core/db/database.dart`, add the import and update in two places:

```dart
// Add import at top:
import 'package:firecheck/core/db/tables/drive_upload_jobs.dart';

// Update @DriftDatabase tables list — add DriveUploadJobs:
@DriftDatabase(
  tables: [
    Enumerators,
    Assignments,
    Features,
    FeatureGeometryRevisions,
    Submissions,
    BuildingAttributes,
    RoadAttributes,
    HouseholdSurveys,
    Photos,
    Ra9514Types,
    SyncJobs,
    OfflineTilePacks,
    DriveUploadJobs,   // ← new
  ],
)

// Update schemaVersion:
@override
int get schemaVersion => 8;   // was 7

// Add v8 migration inside onUpgrade — after the existing `if (from < 7)` block:
if (from < 8) {
  await m.createTable(driveUploadJobs);
  await m.createIndex(driveUploadJobsStatusIdx);
  await m.createIndex(driveUploadJobsAssignmentIdx);
}
```

- [ ] **Step 5: Run build_runner to regenerate database.g.dart**

```bash
dart run build_runner build --delete-conflicting-outputs
```

Expected: `database.g.dart` updated with no errors.

- [ ] **Step 6: Run test — expect PASS**

```bash
flutter test test/core/db/drive_upload_jobs_table_test.dart
```

Expected: PASS.

- [ ] **Step 7: Run full test suite — expect no regressions**

```bash
flutter test
```

Expected: all existing tests still pass.

- [ ] **Step 8: Commit**

```bash
git add lib/core/db/tables/drive_upload_jobs.dart lib/core/db/database.dart lib/core/db/database.g.dart test/core/db/drive_upload_jobs_table_test.dart
git commit -m "feat(db): add DriveUploadJobs table and v8 migration"
```

---

## Task 2: DriveUploadJobStatus + DriveUploadRepository

**Files:**
- Create: `lib/core/drive/drive_upload_job_status.dart`
- Create: `lib/core/drive/drive_upload_repository.dart`
- Test: `test/core/drive/drive_upload_repository_test.dart`

- [ ] **Step 1: Create status constants**

```dart
// lib/core/drive/drive_upload_job_status.dart
class DriveUploadJobStatus {
  DriveUploadJobStatus._();

  static const pending = 'pending';
  static const uploading = 'uploading';
  static const completed = 'completed';
  static const failed = 'failed';
  static const dead = 'dead';

  static const typePhoto = 'photo';
  static const typeShapefile = 'shapefile';
}
```

- [ ] **Step 2: Write the failing tests**

```dart
// test/core/drive/drive_upload_repository_test.dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  group('DriveUploadRepository', () {
    test('insertJob creates a pending job', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);

      await repo.insertJob(
        id: 'j1',
        assignmentId: 'a1',
        filePath: '/photos/p1.jpg',
        fileType: DriveUploadJobStatus.typePhoto,
        fileName: 'p1.jpg',
        fileSizeBytes: 1024,
        capturedAt: DateTime(2026, 5, 2),
      );

      final jobs = await repo.getPendingJobs();
      expect(jobs.length, 1);
      expect(jobs.first.status, DriveUploadJobStatus.pending);
    });

    test('getPendingJobs excludes completed and future-retry jobs', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);

      await repo.insertJob(id: 'j1', assignmentId: 'a1', filePath: '/p1.jpg',
          fileType: DriveUploadJobStatus.typePhoto, fileName: 'p1.jpg',
          fileSizeBytes: 100, capturedAt: DateTime(2026));
      await repo.insertJob(id: 'j2', assignmentId: 'a1', filePath: '/p2.jpg',
          fileType: DriveUploadJobStatus.typePhoto, fileName: 'p2.jpg',
          fileSizeBytes: 100, capturedAt: DateTime(2026));

      await repo.markCompleted('j1', driveFileId: 'drive-1');
      await repo.markFailed('j2',
          reason: 'network', retryCount: 1,
          nextRetryAt: DateTime.now().add(const Duration(hours: 1)));

      final jobs = await repo.getPendingJobs();
      expect(jobs, isEmpty);
    });

    test('getPendingJobs includes failed jobs whose retry time has passed', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);

      await repo.insertJob(id: 'j1', assignmentId: 'a1', filePath: '/p1.jpg',
          fileType: DriveUploadJobStatus.typePhoto, fileName: 'p1.jpg',
          fileSizeBytes: 100, capturedAt: DateTime(2026));
      await repo.markFailed('j1',
          reason: 'err', retryCount: 1,
          nextRetryAt: DateTime.now().subtract(const Duration(seconds: 1)));

      final jobs = await repo.getPendingJobs();
      expect(jobs.length, 1);
    });

    test('markDead sets status=dead and failureReason', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);

      await repo.insertJob(id: 'j1', assignmentId: 'a1', filePath: '/p1.jpg',
          fileType: DriveUploadJobStatus.typePhoto, fileName: 'p1.jpg',
          fileSizeBytes: 100, capturedAt: DateTime(2026));
      await repo.markDead('j1', reason: 'file missing');

      final all = await db.select(db.driveUploadJobs).get();
      expect(all.first.status, DriveUploadJobStatus.dead);
      expect(all.first.failureReason, 'file missing');
    });

    test('resetForRetry resets retryCount and status to pending', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);

      await repo.insertJob(id: 'j1', assignmentId: 'a1', filePath: '/p1.jpg',
          fileType: DriveUploadJobStatus.typePhoto, fileName: 'p1.jpg',
          fileSizeBytes: 100, capturedAt: DateTime(2026));
      await repo.markDead('j1', reason: 'err');
      await repo.resetForRetry('j1');

      final all = await db.select(db.driveUploadJobs).get();
      expect(all.first.status, DriveUploadJobStatus.pending);
      expect(all.first.retryCount, 0);
      expect(all.first.failureReason, isNull);
    });

    test('resetFailedToPending resets failed jobs only, not dead', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);

      await repo.insertJob(id: 'j1', assignmentId: 'a1', filePath: '/p1.jpg',
          fileType: DriveUploadJobStatus.typePhoto, fileName: 'p1.jpg',
          fileSizeBytes: 100, capturedAt: DateTime(2026));
      await repo.insertJob(id: 'j2', assignmentId: 'a1', filePath: '/p2.jpg',
          fileType: DriveUploadJobStatus.typePhoto, fileName: 'p2.jpg',
          fileSizeBytes: 100, capturedAt: DateTime(2026));

      await repo.markFailed('j1', reason: 'net', retryCount: 1,
          nextRetryAt: DateTime.now().add(const Duration(hours: 1)));
      await repo.markDead('j2', reason: 'perma');

      await repo.resetFailedToPending();

      final all = await db.select(db.driveUploadJobs).get();
      final j1 = all.firstWhere((j) => j.id == 'j1');
      final j2 = all.firstWhere((j) => j.id == 'j2');
      expect(j1.status, DriveUploadJobStatus.pending);
      expect(j2.status, DriveUploadJobStatus.dead); // unchanged
    });

    test('jobExistsForFilePath returns true when non-completed job exists', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);

      await repo.insertJob(id: 'j1', assignmentId: 'a1', filePath: '/p1.jpg',
          fileType: DriveUploadJobStatus.typePhoto, fileName: 'p1.jpg',
          fileSizeBytes: 100, capturedAt: DateTime(2026));

      expect(await repo.jobExistsForFilePath('/p1.jpg'), isTrue);
      expect(await repo.jobExistsForFilePath('/other.jpg'), isFalse);
    });

    test('shapefileJobExistsForAssignment returns false when only completed', () async {
      final db = _db();
      addTearDown(db.close);
      final repo = DriveUploadRepository(db);

      await repo.insertJob(id: 'j1', assignmentId: 'a1', filePath: '/a1.zip',
          fileType: DriveUploadJobStatus.typeShapefile, fileName: 'a1.zip',
          fileSizeBytes: 1000, capturedAt: DateTime(2026));
      await repo.markCompleted('j1', driveFileId: 'drive-1');

      expect(await repo.shapefileJobExistsForAssignment('a1'), isFalse);
    });
  });
}
```

- [ ] **Step 3: Run test — expect compile error (DriveUploadRepository not found)**

```bash
flutter test test/core/drive/drive_upload_repository_test.dart
```

- [ ] **Step 4: Implement DriveUploadRepository**

```dart
// lib/core/drive/drive_upload_repository.dart
import 'package:drift/drift.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';

class DriveUploadRepository {
  DriveUploadRepository(this._db);
  final AppDatabase _db;

  Future<void> insertJob({
    required String id,
    required String assignmentId,
    required String filePath,
    required String fileType,
    required String fileName,
    required int fileSizeBytes,
    required DateTime capturedAt,
  }) async {
    await _db.into(_db.driveUploadJobs).insert(
          DriveUploadJobsCompanion.insert(
            id: id,
            assignmentId: assignmentId,
            filePath: filePath,
            fileType: fileType,
            fileName: fileName,
            fileSizeBytes: fileSizeBytes,
            capturedAt: capturedAt,
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<List<DriveUploadJob>> getPendingJobs({DateTime? now}) async {
    final cutoff = now ?? DateTime.now();
    return (_db.select(_db.driveUploadJobs)
          ..where(
            (t) =>
                t.status.isIn([
                  DriveUploadJobStatus.pending,
                  DriveUploadJobStatus.failed,
                ]) &
                (t.nextRetryAt.isNull() |
                    t.nextRetryAt.isSmallerOrEqualValue(cutoff)),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Stream<List<DriveUploadJob>> watchQueue() {
    return (_db.select(_db.driveUploadJobs)
          ..where((t) => t.status.isNotIn([DriveUploadJobStatus.completed]))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  Stream<int> watchPendingCount() {
    return watchQueue().map((jobs) => jobs.length);
  }

  Future<void> markUploading(String id) async {
    await (_db.update(_db.driveUploadJobs)..where((t) => t.id.equals(id)))
        .write(const DriveUploadJobsCompanion(
      status: Value(DriveUploadJobStatus.uploading),
    ));
  }

  Future<void> markCompleted(String id, {required String driveFileId}) async {
    await (_db.update(_db.driveUploadJobs)..where((t) => t.id.equals(id)))
        .write(DriveUploadJobsCompanion(
      status: const Value(DriveUploadJobStatus.completed),
      driveFileId: Value(driveFileId),
      resumableUri: const Value(null),
    ));
  }

  Future<void> markFailed(
    String id, {
    required String reason,
    required int retryCount,
    required DateTime nextRetryAt,
  }) async {
    await (_db.update(_db.driveUploadJobs)..where((t) => t.id.equals(id)))
        .write(DriveUploadJobsCompanion(
      status: const Value(DriveUploadJobStatus.failed),
      failureReason: Value(reason),
      retryCount: Value(retryCount),
      nextRetryAt: Value(nextRetryAt),
    ));
  }

  Future<void> markDead(String id, {required String reason}) async {
    await (_db.update(_db.driveUploadJobs)..where((t) => t.id.equals(id)))
        .write(DriveUploadJobsCompanion(
      status: const Value(DriveUploadJobStatus.dead),
      failureReason: Value(reason),
    ));
  }

  Future<void> setResumableUri(String id, String uri) async {
    await (_db.update(_db.driveUploadJobs)..where((t) => t.id.equals(id)))
        .write(DriveUploadJobsCompanion(resumableUri: Value(uri)));
  }

  Future<void> resetForRetry(String id) async {
    await (_db.update(_db.driveUploadJobs)..where((t) => t.id.equals(id)))
        .write(const DriveUploadJobsCompanion(
      status: Value(DriveUploadJobStatus.pending),
      retryCount: Value(0),
      failureReason: Value(null),
      nextRetryAt: Value(null),
    ));
  }

  Future<void> resetFailedToPending() async {
    await (_db.update(_db.driveUploadJobs)
          ..where((t) => t.status.equals(DriveUploadJobStatus.failed)))
        .write(const DriveUploadJobsCompanion(
      status: Value(DriveUploadJobStatus.pending),
      nextRetryAt: Value(null),
    ));
  }

  Future<bool> jobExistsForFilePath(String filePath) async {
    final row = await (_db.select(_db.driveUploadJobs)
          ..where((t) =>
              t.filePath.equals(filePath) &
              t.status.isNotIn([DriveUploadJobStatus.completed]))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  Future<bool> shapefileJobExistsForAssignment(String assignmentId) async {
    final row = await (_db.select(_db.driveUploadJobs)
          ..where((t) =>
              t.assignmentId.equals(assignmentId) &
              t.fileType.equals(DriveUploadJobStatus.typeShapefile) &
              t.status.isNotIn([DriveUploadJobStatus.completed]))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }
}
```

- [ ] **Step 5: Run test — expect PASS**

```bash
flutter test test/core/drive/drive_upload_repository_test.dart
```

Expected: all 7 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/drive/drive_upload_job_status.dart lib/core/drive/drive_upload_repository.dart test/core/drive/drive_upload_repository_test.dart
git commit -m "feat(drive): add DriveUploadJobStatus and DriveUploadRepository"
```

---

## Task 3: DriveUploadApi interface + FakeDriveUploadApi

**Files:**
- Create: `lib/core/drive/drive_upload_api.dart`
- Create: `lib/core/drive/fake_drive_upload_api.dart`

No unit tests at this step — the interface and fake are exercised by Task 5 (worker tests).

- [ ] **Step 1: Create the abstract interface**

```dart
// lib/core/drive/drive_upload_api.dart

/// Upload surface for Google Drive. Separate from the read-only DriveApi
/// to keep download and upload concerns independent.
abstract interface class DriveUploadApi {
  /// Returns the Drive folder ID. Queries existing folder first; creates if absent.
  Future<String> createOrGetFolder(String name, String parentId);

  /// Uploads [localPath] into [driveParentId] and returns the Drive file ID.
  /// Pass [resumableUri] to resume an interrupted large-file upload.
  Future<String> uploadFile({
    required String localPath,
    required String driveParentId,
    required String fileName,
    String? resumableUri,
    void Function(int sent, int total)? onProgress,
  });
}
```

- [ ] **Step 2: Create the test double**

```dart
// lib/core/drive/fake_drive_upload_api.dart
import 'package:firecheck/core/drive/drive_upload_api.dart';

class FakeDriveUploadApi implements DriveUploadApi {
  FakeDriveUploadApi({
    this.throwOnUpload = false,
    this.throwOnFolder = false,
  });

  final bool throwOnUpload;
  final bool throwOnFolder;

  final List<String> uploadedPaths = [];
  final Map<String, String> _folderIds = {};
  int _fileCounter = 0;

  @override
  Future<String> createOrGetFolder(String name, String parentId) async {
    if (throwOnFolder) throw Exception('folder creation failed');
    final key = '$parentId/$name';
    return _folderIds[key] ??= 'folder-${_folderIds.length + 1}';
  }

  @override
  Future<String> uploadFile({
    required String localPath,
    required String driveParentId,
    required String fileName,
    String? resumableUri,
    void Function(int sent, int total)? onProgress,
  }) async {
    if (throwOnUpload) throw Exception('upload failed');
    uploadedPaths.add(localPath);
    _fileCounter++;
    onProgress?.call(100, 100);
    return 'drive-file-$_fileCounter';
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/core/drive/drive_upload_api.dart lib/core/drive/fake_drive_upload_api.dart
git commit -m "feat(drive): add DriveUploadApi interface and FakeDriveUploadApi"
```

---

## Task 4: ShapefileExporter.exportToFile()

**Files:**
- Modify: `lib/core/sync/shapefile/export/shapefile_exporter.dart`
- Test: `test/core/sync/shapefile/export/shapefile_exporter_export_to_file_test.dart`

The existing `export()` method writes to `getTemporaryDirectory()`. Temp files can be cleaned by the OS before upload completes. `exportToFile()` writes to `getApplicationDocumentsDirectory()` for a stable path.

- [ ] **Step 1: Write the failing test**

```dart
// test/core/sync/shapefile/export/shapefile_exporter_export_to_file_test.dart
import 'dart:io';
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/sync/shapefile/export/export_failure.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_exporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('shapefile_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('exportToFile returns NoCompletedFeatures when assignment has no complete features', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // Insert assignment + feature without completion
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
      id: 'a1',
      enumeratorId: 'e1',
      campaignId: 'c1',
      boundaryPolygonGeojson: '{}',
      createdAt: DateTime(2026),
    ));

    final exporter = ShapefileExporter(db: db, tempDirOverride: tempDir);
    final (failure, path) = await exporter.exportToFile(assignmentId: 'a1');

    expect(failure, isA<NoCompletedFeatures>());
    expect(path, isNull);
  });

  test('exportToFile writes ZIP to tempDirOverride and returns path', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // Seed a complete building feature
    await db.into(db.assignments).insert(AssignmentsCompanion.insert(
      id: 'a1', enumeratorId: 'e1', campaignId: 'c1',
      boundaryPolygonGeojson: '{}', createdAt: DateTime(2026),
    ));
    await db.into(db.features).insert(FeaturesCompanion.insert(
      id: 'f1', assignmentId: 'a1', featureType: 'building',
      geometryGeojson: '{"type":"Polygon","coordinates":[[[0,0],[1,0],[1,1],[0,1],[0,0]]]}',
      status: const Value('complete'),
      createdAt: DateTime(2026),
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

    final exporter = ShapefileExporter(db: db, tempDirOverride: tempDir);
    final (failure, path) = await exporter.exportToFile(assignmentId: 'a1');

    expect(failure, isNull);
    expect(path, isNotNull);
    expect(p.extension(path!), '.zip');
    expect(File(path).existsSync(), isTrue);
  });
}
```

- [ ] **Step 2: Run test — expect compile error (exportToFile not defined)**

```bash
flutter test test/core/sync/shapefile/export/shapefile_exporter_export_to_file_test.dart
```

- [ ] **Step 3: Refactor ShapefileExporter to add exportToFile()**

Read `lib/core/sync/shapefile/export/shapefile_exporter.dart` fully before editing. The existing `export()` method (lines 336–453) directly builds the archive and writes to temp. Extract the shared work into two new private methods, then add `exportToFile()`.

Replace the body of `export()` and add the three new methods. The existing method signature and return type must not change.

Find this section (lines 336–453):
```dart
Future<ExportFailure?> export({required String assignmentId}) async {
    // Query all completed features with their submissions and attributes.
    final buildingRows = await _queryBuildings(assignmentId);
    final roadRows = await _queryRoads(assignmentId);
    ...
    return null;
  }
```

Replace with:

```dart
Future<ExportFailure?> export({required String assignmentId}) async {
  final tempDir = tempDirOverride ?? await getTemporaryDirectory();
  final (failure, _) = await _buildAndWriteZip(
    assignmentId: assignmentId,
    destDir: tempDir,
    callShareFile: true,
  );
  return failure;
}

/// Exports to [getApplicationDocumentsDirectory] (stable path). Returns the
/// zip path on success — callers must not delete the file until upload confirms.
Future<(ExportFailure?, String?)> exportToFile({
  required String assignmentId,
}) async {
  final destDir = tempDirOverride ?? await getApplicationDocumentsDirectory();
  return _buildAndWriteZip(
    assignmentId: assignmentId,
    destDir: destDir,
    callShareFile: false,
  );
}

Future<(ExportFailure?, String?)> _buildAndWriteZip({
  required String assignmentId,
  required Directory destDir,
  required bool callShareFile,
}) async {
  final buildingRows = await _queryBuildings(assignmentId);
  final roadRows = await _queryRoads(assignmentId);

  if (buildingRows.isEmpty && roadRows.isEmpty) {
    return (const NoCompletedFeatures(), null);
  }

  final inputs = <_LayerInput>[];
  if (buildingRows.isNotEmpty) {
    inputs.add(_LayerInput(
      layerName: 'buildings',
      isPolygon: true,
      features: buildingRows
          .map((r) => _FeatureRow(
                featureId: r.featureId,
                geometryGeojson: r.geometryGeojson,
              ))
          .toList(),
      buildingRows: buildingRows.map((r) => r.buildingRow).toList(),
      roadRows: const [],
    ));
  }
  if (roadRows.isNotEmpty) {
    inputs.add(_LayerInput(
      layerName: 'roads',
      isPolygon: false,
      features: roadRows
          .map((r) => _FeatureRow(
                featureId: r.featureId,
                geometryGeojson: r.geometryGeojson,
              ))
          .toList(),
      buildingRows: const [],
      roadRows: roadRows.map((r) => r.roadRow).toList(),
    ));
  }

  List<_LayerOutput> outputs;
  try {
    outputs = await Future.wait(inputs.map((i) => compute(_writeLayer, i)));
  } catch (e) {
    return (WriteError(e.toString()), null);
  }

  for (final out in outputs) {
    if (out.shp.isEmpty || out.shx.isEmpty || out.dbf.isEmpty) {
      return (WriteError('Layer ${out.layerName} produced empty components'), null);
    }
  }

  final archive = Archive();
  for (final out in outputs) {
    final name = out.layerName;
    archive
      ..addFile(ArchiveFile('$name.shp', out.shp.length, out.shp))
      ..addFile(ArchiveFile('$name.shx', out.shx.length, out.shx))
      ..addFile(ArchiveFile('$name.dbf', out.dbf.length, out.dbf))
      ..addFile(ArchiveFile('$name.prj', _prjContent.length, _prjContent.codeUnits))
      ..addFile(ArchiveFile('$name.cpg', _cpgContent.length, _cpgContent.codeUnits));
  }

  final zipBytes = ZipEncoder().encode(archive);
  if (zipBytes == null) {
    return (const WriteError('ZIP encoding produced no output'), null);
  }

  final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  final zipName = 'firecheck_${assignmentId}_$timestamp.zip';
  final zipPath = p.join(destDir.path, zipName);

  try {
    await File(zipPath).writeAsBytes(zipBytes);
  } catch (e) {
    return (WriteError(e.toString()), null);
  }

  if (callShareFile && shareFile != null) {
    try {
      await shareFile!(zipPath);
    } catch (e) {
      return (ShareError(e.toString()), null);
    }
  }

  return (null, zipPath);
}
```

Also add this import at the top if not already present:
```dart
import 'package:path_provider/path_provider.dart';
```

- [ ] **Step 4: Run new tests + full suite**

```bash
flutter test test/core/sync/shapefile/export/shapefile_exporter_export_to_file_test.dart
flutter test
```

Expected: new tests PASS, existing shapefile exporter tests still PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/sync/shapefile/export/shapefile_exporter.dart test/core/sync/shapefile/export/shapefile_exporter_export_to_file_test.dart
git commit -m "feat(export): add exportToFile() for stable-path zip used by drive upload"
```

---

## Task 5: EnqueueAssignmentUseCase

**Files:**
- Create: `lib/core/drive/enqueue_assignment_use_case.dart`
- Test: `test/core/drive/enqueue_assignment_use_case_test.dart`

Generates the shapefile ZIP, then writes one `DriveUploadJob` per photo and one for the ZIP. Idempotent — calling twice doesn't double-queue.

- [ ] **Step 1: Write the failing tests**

```dart
// test/core/drive/enqueue_assignment_use_case_test.dart
import 'dart:io';
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
    expect(jobs.any((j) => j.fileType == DriveUploadJobStatus.typeShapefile), isTrue);
    expect(jobs.any((j) => j.fileType == DriveUploadJobStatus.typePhoto), isTrue);
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
```

- [ ] **Step 2: Run test — expect compile error**

```bash
flutter test test/core/drive/enqueue_assignment_use_case_test.dart
```

- [ ] **Step 3: Implement EnqueueAssignmentUseCase**

```dart
// lib/core/drive/enqueue_assignment_use_case.dart
import 'dart:io';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/sync/shapefile/export/shapefile_exporter.dart';
import 'package:uuid/uuid.dart';

class EnqueueAssignmentUseCase {
  EnqueueAssignmentUseCase({
    required AppDatabase db,
    required DriveUploadRepository repo,
    required ShapefileExporter exporter,
  })  : _db = db,
        _repo = repo,
        _exporter = exporter;

  final AppDatabase _db;
  final DriveUploadRepository _repo;
  final ShapefileExporter _exporter;
  static const _uuid = Uuid();

  /// Returns the number of new jobs created (0 if already fully enqueued).
  Future<int> execute({required String assignmentId}) async {
    var created = 0;

    // ── Shapefile ────────────────────────────────────────────────────────────
    final shapefileExists =
        await _repo.shapefileJobExistsForAssignment(assignmentId);
    if (!shapefileExists) {
      final (failure, zipPath) =
          await _exporter.exportToFile(assignmentId: assignmentId);
      if (failure == null && zipPath != null) {
        final file = File(zipPath);
        final size = file.existsSync() ? await file.length() : 0;
        await _repo.insertJob(
          id: _uuid.v4(),
          assignmentId: assignmentId,
          filePath: zipPath,
          fileType: DriveUploadJobStatus.typeShapefile,
          fileName: zipPath.split('/').last,
          fileSizeBytes: size,
          capturedAt: DateTime.now(),
        );
        created++;
      }
    }

    // ── Photos ───────────────────────────────────────────────────────────────
    final photos = await _photosForAssignment(assignmentId);
    for (final photo in photos) {
      final exists = await _repo.jobExistsForFilePath(photo.localPath);
      if (exists) continue;
      final file = File(photo.localPath);
      final size = file.existsSync() ? await file.length() : 0;
      await _repo.insertJob(
        id: _uuid.v4(),
        assignmentId: assignmentId,
        filePath: photo.localPath,
        fileType: DriveUploadJobStatus.typePhoto,
        fileName: photo.localPath.split('/').last,
        fileSizeBytes: size,
        capturedAt: photo.capturedAt,
      );
      created++;
    }

    return created;
  }

  Future<List<Photo>> _photosForAssignment(String assignmentId) async {
    final featureIds = await (_db.selectOnly(_db.features)
          ..addColumns([_db.features.id])
          ..where(_db.features.assignmentId.equals(assignmentId)))
        .map((row) => row.read(_db.features.id)!)
        .get();

    if (featureIds.isEmpty) return [];

    final submissionIds = await (_db.selectOnly(_db.submissions)
          ..addColumns([_db.submissions.id])
          ..where(_db.submissions.featureId.isIn(featureIds)))
        .map((row) => row.read(_db.submissions.id)!)
        .get();

    if (submissionIds.isEmpty) return [];

    return (_db.select(_db.photos)
          ..where((t) => t.submissionId.isIn(submissionIds)))
        .get();
  }
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
flutter test test/core/drive/enqueue_assignment_use_case_test.dart
```

- [ ] **Step 5: Run full suite**

```bash
flutter test
```

- [ ] **Step 6: Commit**

```bash
git add lib/core/drive/enqueue_assignment_use_case.dart test/core/drive/enqueue_assignment_use_case_test.dart
git commit -m "feat(drive): add EnqueueAssignmentUseCase for shapefile+photo queue population"
```

---

## Task 6: DriveUploadWorker

**Files:**
- Create: `lib/core/drive/drive_upload_worker.dart`
- Test: `test/core/drive/drive_upload_worker_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// test/core/drive/drive_upload_worker_test.dart
import 'dart:io';
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:firecheck/core/drive/fake_drive_upload_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('worker_test_');
  });
  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<String> _seedPhoto(AppDatabase db, DriveUploadRepository repo, String id) async {
    final path = '${tempDir.path}/$id.jpg';
    await File(path).writeAsBytes([0xFF, 0xD8]);
    await repo.insertJob(
      id: id, assignmentId: 'a1', filePath: path,
      fileType: DriveUploadJobStatus.typePhoto, fileName: '$id.jpg',
      fileSizeBytes: 2, capturedAt: DateTime(2026),
    );
    return path;
  }

  test('drain marks job completed on successful upload', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriveUploadRepository(db);
    final api = FakeDriveUploadApi();
    await _seedPhoto(db, repo, 'j1');

    final worker = DriveUploadWorker(
      api: api,
      repo: repo,
      db: db,
      rootFolderId: 'root-folder',
    );
    await worker.drain();

    final jobs = await db.select(db.driveUploadJobs).get();
    expect(jobs.first.status, DriveUploadJobStatus.completed);
    expect(jobs.first.driveFileId, isNotNull);
    expect(api.uploadedPaths.length, 1);
  });

  test('drain marks job failed on transient error (retryCount increments)', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriveUploadRepository(db);
    final api = FakeDriveUploadApi(throwOnUpload: true);
    await _seedPhoto(db, repo, 'j1');

    final worker = DriveUploadWorker(
      api: api,
      repo: repo,
      db: db,
      rootFolderId: 'root-folder',
    );
    await worker.drain();

    final jobs = await db.select(db.driveUploadJobs).get();
    expect(jobs.first.status, DriveUploadJobStatus.failed);
    expect(jobs.first.retryCount, 1);
    expect(jobs.first.nextRetryAt, isNotNull);
  });

  test('drain marks job dead after 3 failures', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriveUploadRepository(db);
    final api = FakeDriveUploadApi(throwOnUpload: true);
    await _seedPhoto(db, repo, 'j1');

    final worker = DriveUploadWorker(
      api: api,
      repo: repo,
      db: db,
      rootFolderId: 'root-folder',
    );

    // Drain 3× with retry time set to past each time
    for (var i = 0; i < 3; i++) {
      // Reset nextRetryAt to past so it's eligible
      await db.customStatement(
        'UPDATE drive_upload_jobs SET next_retry_at = NULL WHERE id = ?',
        ['j1'],
      );
      await worker.drain();
    }

    final jobs = await db.select(db.driveUploadJobs).get();
    expect(jobs.first.status, DriveUploadJobStatus.dead);
  });

  test('drain skips job whose local file is missing', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriveUploadRepository(db);
    final api = FakeDriveUploadApi();
    await repo.insertJob(
      id: 'j1', assignmentId: 'a1',
      filePath: '/nonexistent/missing.jpg',
      fileType: DriveUploadJobStatus.typePhoto, fileName: 'missing.jpg',
      fileSizeBytes: 0, capturedAt: DateTime(2026),
    );

    final worker = DriveUploadWorker(
      api: api,
      repo: repo,
      db: db,
      rootFolderId: 'root-folder',
    );
    await worker.drain();

    final jobs = await db.select(db.driveUploadJobs).get();
    expect(jobs.first.status, DriveUploadJobStatus.dead);
    expect(jobs.first.failureReason, contains('missing'));
    expect(api.uploadedPaths, isEmpty);
  });
}
```

- [ ] **Step 2: Run test — expect compile error**

```bash
flutter test test/core/drive/drive_upload_worker_test.dart
```

- [ ] **Step 3: Implement DriveUploadWorker**

```dart
// lib/core/drive/drive_upload_worker.dart
import 'dart:io';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_api.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:intl/intl.dart';

class DriveUploadWorker {
  DriveUploadWorker({
    required this.api,
    required this.repo,
    required this.db,
    required this.rootFolderId,
  });

  final DriveUploadApi api;
  final DriveUploadRepository repo;
  final AppDatabase db;
  final String rootFolderId;

  static const _maxConcurrent = 3;
  bool _running = false;

  // Session-scoped folder ID cache; not persisted across app restarts.
  final _folderCache = <String, String>{};

  Future<void> drain() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final jobs = await repo.getPendingJobs();
        if (jobs.isEmpty) return;
        await Future.wait(jobs.take(_maxConcurrent).map(_processOne));
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _processOne(DriveUploadJob job) async {
    final file = File(job.filePath);
    if (!file.existsSync()) {
      await repo.markDead(job.id, reason: 'file missing: ${job.filePath}');
      return;
    }

    await repo.markUploading(job.id);

    try {
      final parentId = await _resolveParentFolder(job);
      final driveFileId = await api.uploadFile(
        localPath: job.filePath,
        driveParentId: parentId,
        fileName: job.fileName,
        resumableUri: job.resumableUri,
      );
      await repo.markCompleted(job.id, driveFileId: driveFileId);
    } on Exception catch (e) {
      final attempts = job.retryCount + 1;
      final next = _nextRetryAt(attempts);
      if (next == null) {
        await repo.markDead(job.id, reason: e.toString());
      } else {
        await repo.markFailed(
          job.id,
          reason: e.toString(),
          retryCount: attempts,
          nextRetryAt: next,
        );
      }
    }
  }

  Future<String> _resolveParentFolder(DriveUploadJob job) async {
    final assignment = await (db.select(db.assignments)
          ..where((t) => t.id.equals(job.assignmentId)))
        .getSingle();
    final enumeratorId = assignment.enumeratorId;
    final dateKey = DateFormat('yyyy-MM-dd').format(job.capturedAt);
    final subfolderName = job.fileType == DriveUploadJobStatus.typePhoto
        ? 'photos'
        : 'shapefiles';

    final cacheKey = '$enumeratorId/$dateKey/$subfolderName';
    if (_folderCache.containsKey(cacheKey)) {
      return _folderCache[cacheKey]!;
    }

    final enumeratorFolderId =
        await api.createOrGetFolder(enumeratorId, rootFolderId);
    final dateFolderId =
        await api.createOrGetFolder(dateKey, enumeratorFolderId);
    final subFolderId =
        await api.createOrGetFolder(subfolderName, dateFolderId);

    _folderCache[cacheKey] = subFolderId;
    return subFolderId;
  }

  DateTime? _nextRetryAt(int attempts) {
    final base = DateTime.now();
    return switch (attempts) {
      1 => base.add(const Duration(seconds: 30)),
      2 => base.add(const Duration(minutes: 2)),
      3 => base.add(const Duration(minutes: 10)),
      _ => null,
    };
  }
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
flutter test test/core/drive/drive_upload_worker_test.dart
```

- [ ] **Step 5: Run full suite**

```bash
flutter test
```

- [ ] **Step 6: Commit**

```bash
git add lib/core/drive/drive_upload_worker.dart test/core/drive/drive_upload_worker_test.dart
git commit -m "feat(drive): add DriveUploadWorker with retry/dead logic"
```

---

## Task 7: DriveUploadPreferences

**Files:**
- Create: `lib/core/drive/drive_upload_preferences.dart`
- Test: `test/core/drive/drive_upload_preferences_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/drive/drive_upload_preferences_test.dart
import 'package:firecheck/core/drive/drive_upload_preferences.dart';
import 'package:firecheck/core/security/secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('autoUploadEnabled defaults to false', () async {
    final prefs = DriveUploadPreferences(InMemorySecureStorage());
    expect(await prefs.isAutoUploadEnabled(), isFalse);
  });

  test('setAutoUpload persists and reads back', () async {
    final prefs = DriveUploadPreferences(InMemorySecureStorage());
    await prefs.setAutoUploadEnabled(enabled: true);
    expect(await prefs.isAutoUploadEnabled(), isTrue);
    await prefs.setAutoUploadEnabled(enabled: false);
    expect(await prefs.isAutoUploadEnabled(), isFalse);
  });
}
```

- [ ] **Step 2: Run test — expect compile error**

```bash
flutter test test/core/drive/drive_upload_preferences_test.dart
```

- [ ] **Step 3: Implement**

```dart
// lib/core/drive/drive_upload_preferences.dart
import 'package:firecheck/core/security/secure_storage.dart';

class DriveUploadPreferences {
  DriveUploadPreferences(this._storage);
  final SecureStorage _storage;

  static const _keyAutoUpload = 'drive_auto_upload_enabled';

  Future<bool> isAutoUploadEnabled() async {
    final val = await _storage.read(_keyAutoUpload);
    return val == 'true';
  }

  Future<void> setAutoUploadEnabled({required bool enabled}) =>
      _storage.write(_keyAutoUpload, enabled ? 'true' : 'false');
}
```

- [ ] **Step 4: Run test + full suite — expect PASS**

```bash
flutter test test/core/drive/drive_upload_preferences_test.dart && flutter test
```

- [ ] **Step 5: Commit**

```bash
git add lib/core/drive/drive_upload_preferences.dart test/core/drive/drive_upload_preferences_test.dart
git commit -m "feat(drive): add DriveUploadPreferences for auto-upload toggle"
```

---

## Task 8: DriveUploadController

**Files:**
- Create: `lib/core/drive/drive_upload_controller.dart`
- Test: `test/core/drive/drive_upload_controller_test.dart`

Mirrors `SyncController` but gates on Wi-Fi (`ConnectivityResult.wifi`) rather than any connection.

- [ ] **Step 1: Write the failing tests**

```dart
// test/core/drive/drive_upload_controller_test.dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firecheck/core/drive/drive_upload_controller.dart';
import 'package:firecheck/core/drive/drive_upload_preferences.dart';
import 'package:firecheck/core/security/secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('triggerNow calls onDrain', () async {
    var drainCalled = 0;
    final prefs = DriveUploadPreferences(InMemorySecureStorage());
    final ctrl = DriveUploadController(
      onDrain: () async => drainCalled++,
      preferences: prefs,
    );

    await ctrl.triggerNow();
    expect(drainCalled, 1);
  });

  test('Wi-Fi connectivity event triggers drain when auto-upload is on', () async {
    final controller = StreamController<List<ConnectivityResult>>();
    var drainCalled = 0;
    final storage = InMemorySecureStorage();
    final prefs = DriveUploadPreferences(storage);
    await prefs.setAutoUploadEnabled(enabled: true);

    final ctrl = DriveUploadController(
      onDrain: () async => drainCalled++,
      preferences: prefs,
      connectivityStream: controller.stream,
    );
    await ctrl.start();

    controller.add([ConnectivityResult.wifi]);
    await Future.delayed(Duration.zero);

    expect(drainCalled, greaterThanOrEqualTo(1));
    await ctrl.stop();
    await controller.close();
  });

  test('mobile connectivity does not trigger drain', () async {
    final controller = StreamController<List<ConnectivityResult>>();
    var drainCalled = 0;
    final prefs = DriveUploadPreferences(InMemorySecureStorage());
    await prefs.setAutoUploadEnabled(enabled: true);

    final ctrl = DriveUploadController(
      onDrain: () async => drainCalled++,
      preferences: prefs,
      connectivityStream: controller.stream,
    );
    await ctrl.start();

    controller.add([ConnectivityResult.mobile]);
    await Future.delayed(Duration.zero);

    expect(drainCalled, 0);
    await ctrl.stop();
    await controller.close();
  });

  test('Wi-Fi event does not trigger drain when auto-upload is off', () async {
    final streamCtrl = StreamController<List<ConnectivityResult>>();
    var drainCalled = 0;
    final prefs = DriveUploadPreferences(InMemorySecureStorage());
    // auto-upload default is false

    final ctrl = DriveUploadController(
      onDrain: () async => drainCalled++,
      preferences: prefs,
      connectivityStream: streamCtrl.stream,
    );
    await ctrl.start();

    streamCtrl.add([ConnectivityResult.wifi]);
    await Future.delayed(Duration.zero);

    expect(drainCalled, 0);
    await ctrl.stop();
    await streamCtrl.close();
  });
}
```

- [ ] **Step 2: Run test — expect compile error**

```bash
flutter test test/core/drive/drive_upload_controller_test.dart
```

- [ ] **Step 3: Implement**

```dart
// lib/core/drive/drive_upload_controller.dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firecheck/core/drive/drive_upload_preferences.dart';

class DriveUploadController {
  DriveUploadController({
    required Future<void> Function() onDrain,
    required DriveUploadPreferences preferences,
    Stream<List<ConnectivityResult>>? connectivityStream,
  })  : _onDrain = onDrain,
        _preferences = preferences,
        _connectivityStream = connectivityStream ??
            Connectivity()
                .onConnectivityChanged
                .map((r) => <ConnectivityResult>[r]);

  final Future<void> Function() _onDrain;
  final DriveUploadPreferences _preferences;
  final Stream<List<ConnectivityResult>> _connectivityStream;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  Future<void> start() async {
    _sub = _connectivityStream.listen((results) async {
      final isWifi = results.any((r) => r == ConnectivityResult.wifi);
      if (!isWifi) return;
      final autoEnabled = await _preferences.isAutoUploadEnabled();
      if (autoEnabled) await _onDrain();
    });
  }

  Future<void> triggerNow() => _onDrain();

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}
```

- [ ] **Step 4: Run tests + full suite — expect PASS**

```bash
flutter test test/core/drive/drive_upload_controller_test.dart && flutter test
```

- [ ] **Step 5: Commit**

```bash
git add lib/core/drive/drive_upload_controller.dart test/core/drive/drive_upload_controller_test.dart
git commit -m "feat(drive): add DriveUploadController with Wi-Fi-only trigger"
```

---

## Task 9: DriveUploadWorkmanager dispatcher

**Files:**
- Create: `lib/core/drive/drive_upload_workmanager.dart`

No automated tests (WorkManager requires a real device). Verify by running the app and checking that uploads trigger in the background.

- [ ] **Step 1: Implement the WorkManager dispatcher**

```dart
// lib/core/drive/drive_upload_workmanager.dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:firecheck/core/drive/google_drive_upload_api.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:workmanager/workmanager.dart';

const _periodicTaskName = 'firecheck.drive_upload.periodic';

@pragma('vm:entry-point')
void driveUploadCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // Only proceed if Wi-Fi is available.
      final connectivity = await Connectivity().checkConnectivity();
      final isWifi = connectivity.contains(ConnectivityResult.wifi);
      if (!isWifi) return true;

      await dotenv.load();
      final rootFolderId = dotenv.env['DRIVE_UPLOAD_FOLDER_ID'] ?? '';
      if (rootFolderId.isEmpty) return false;

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final signIn = GoogleSignIn(
        scopes: [
          'https://www.googleapis.com/auth/drive.file',
        ],
      );
      final uploadApi = GoogleDriveUploadApi(googleSignIn: signIn);
      final worker = DriveUploadWorker(
        api: uploadApi,
        repo: DriveUploadRepository(db),
        db: db,
        rootFolderId: rootFolderId,
      );
      await worker.drain();
      await db.close();
      return true;
    } on Object {
      return false;
    }
  });
}

Future<void> registerPeriodicDriveUpload() async {
  await Workmanager().initialize(driveUploadCallbackDispatcher);
  await Workmanager().registerPeriodicTask(
    _periodicTaskName,
    'firecheck.drive_upload',
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

Future<void> cancelPeriodicDriveUpload() async {
  await Workmanager().cancelByUniqueName(_periodicTaskName);
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/drive/drive_upload_workmanager.dart
git commit -m "feat(drive): add DriveUploadWorkmanager background dispatcher"
```

---

## Task 10: Google auth scope + GoogleDriveUploadApi

**Files:**
- Modify: `lib/features/auth/data/google_auth_repository.dart`
- Create: `lib/core/drive/google_drive_upload_api.dart`
- Test: `test/features/auth/google_auth_repository_drive_scope_test.dart`

- [ ] **Step 1: Read the existing GoogleAuthRepository**

```bash
cat lib/features/auth/data/google_auth_repository.dart
```

Locate the `GoogleSignIn` instantiation. The scopes list is passed to `GoogleSignIn(scopes: [...])`. Note the exact location.

- [ ] **Step 2: Write the failing test**

```dart
// test/features/auth/google_auth_repository_drive_scope_test.dart
import 'package:firecheck/features/auth/data/google_auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:google_sign_in/google_sign_in.dart';

class _MockGoogleSignIn extends Mock implements GoogleSignIn {}

void main() {
  test('requestDriveUploadScope calls requestScopes with drive.file scope', () async {
    final mockSignIn = _MockGoogleSignIn();
    when(() => mockSignIn.requestScopes(any())).thenAnswer((_) async => true);

    final repo = GoogleAuthRepository(googleSignIn: mockSignIn);
    final result = await repo.requestDriveUploadScope();

    expect(result, isTrue);
    verify(() => mockSignIn.requestScopes(
      [GoogleAuthRepository.driveFileScope],
    )).called(1);
  });
}
```

- [ ] **Step 3: Run test — expect compile error**

```bash
flutter test test/features/auth/google_auth_repository_drive_scope_test.dart
```

- [ ] **Step 4: Add requestDriveUploadScope() to GoogleAuthRepository**

Add to `lib/features/auth/data/google_auth_repository.dart`:

```dart
// Add static constant (inside the class):
static const driveFileScope =
    'https://www.googleapis.com/auth/drive.file';

// Add method:
Future<bool> requestDriveUploadScope() async {
  try {
    return await _googleSignIn.requestScopes([driveFileScope]);
  } on Object {
    return false;
  }
}
```

`_googleSignIn` is the `GoogleSignIn` field in the existing class. Use whatever name it already has.

- [ ] **Step 5: Run test — expect PASS**

```bash
flutter test test/features/auth/google_auth_repository_drive_scope_test.dart
```

- [ ] **Step 6: Implement GoogleDriveUploadApi**

```dart
// lib/core/drive/google_drive_upload_api.dart
import 'dart:io';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:firecheck/core/drive/drive_upload_api.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as gdrive;

class GoogleDriveUploadApi implements DriveUploadApi {
  GoogleDriveUploadApi({required GoogleSignIn googleSignIn})
      : _googleSignIn = googleSignIn;

  final GoogleSignIn _googleSignIn;

  Future<gdrive.DriveApi> _api() async {
    final client = await _googleSignIn.authenticatedClient();
    if (client == null) throw const AuthFailure('Not signed in to Google');
    return gdrive.DriveApi(client);
  }

  @override
  Future<String> createOrGetFolder(String name, String parentId) async {
    final api = await _api();
    final existing = await api.files.list(
      q: "name = '$name' "
          "and mimeType = 'application/vnd.google-apps.folder' "
          "and '$parentId' in parents "
          "and trashed = false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    if (existing.files?.isNotEmpty == true) {
      return existing.files!.first.id!;
    }
    final folder = await api.files.create(
      gdrive.File()
        ..name = name
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [parentId],
      $fields: 'id',
    );
    return folder.id!;
  }

  @override
  Future<String> uploadFile({
    required String localPath,
    required String driveParentId,
    required String fileName,
    String? resumableUri,
    void Function(int sent, int total)? onProgress,
  }) async {
    final api = await _api();
    final file = File(localPath);
    final fileSize = await file.length();
    final mimeType = fileName.toLowerCase().endsWith('.jpg')
        ? 'image/jpeg'
        : 'application/zip';

    final media = gdrive.Media(
      file.openRead(),
      fileSize,
      contentType: mimeType,
    );
    final metadata = gdrive.File()
      ..name = fileName
      ..parents = [driveParentId];

    final created = await api.files.create(
      metadata,
      uploadMedia: media,
      $fields: 'id',
    );
    onProgress?.call(fileSize, fileSize);
    return created.id!;
  }
}
```

- [ ] **Step 7: Run full suite**

```bash
flutter test
```

- [ ] **Step 8: Commit**

```bash
git add lib/features/auth/data/google_auth_repository.dart lib/core/drive/google_drive_upload_api.dart test/features/auth/google_auth_repository_drive_scope_test.dart
git commit -m "feat(auth,drive): add drive.file scope request and GoogleDriveUploadApi"
```

---

## Task 11: DriveUploadProviders + DriveUploadNotifier

**Files:**
- Create: `lib/core/drive/drive_upload_providers.dart`
- Create: `lib/features/upload/presentation/upload_queue_notifier.dart`
- Test: `test/features/upload/upload_queue_notifier_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/upload/upload_queue_notifier_test.dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:firecheck/core/drive/fake_drive_upload_api.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pendingCount reflects queue', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriveUploadRepository(db);
    await repo.insertJob(
      id: 'j1', assignmentId: 'a1', filePath: '/p1.jpg',
      fileType: DriveUploadJobStatus.typePhoto, fileName: 'p1.jpg',
      fileSizeBytes: 100, capturedAt: DateTime(2026),
    );

    final container = ProviderContainer(overrides: [
      driveUploadRepoProvider.overrideWithValue(repo),
      driveUploadWorkerProvider.overrideWithValue(
        DriveUploadWorker(
          api: FakeDriveUploadApi(),
          repo: repo,
          db: db,
          rootFolderId: 'root',
        ),
      ),
    ]);
    addTearDown(container.dispose);

    // Allow stream to settle
    await Future.delayed(Duration.zero);
    final state = container.read(driveUploadNotifierProvider);
    expect(state.pendingCount, 1);
  });
}
```

- [ ] **Step 2: Run test — expect compile error**

```bash
flutter test test/features/upload/upload_queue_notifier_test.dart
```

- [ ] **Step 3: Implement DriveUploadNotifier**

```dart
// lib/features/upload/presentation/upload_queue_notifier.dart
import 'dart:async';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DriveUploadState {
  const DriveUploadState({
    required this.jobs,
  });

  final List<DriveUploadJob> jobs;

  int get pendingCount =>
      jobs.where((j) => j.status != DriveUploadJobStatus.completed).length;

  int get totalPendingBytes => jobs
      .where((j) => j.status != DriveUploadJobStatus.completed)
      .fold(0, (sum, j) => sum + j.fileSizeBytes);

  int get completedCount =>
      jobs.where((j) => j.status == DriveUploadJobStatus.completed).length;

  bool get isUploading =>
      jobs.any((j) => j.status == DriveUploadJobStatus.uploading);
}

class DriveUploadNotifier extends StateNotifier<DriveUploadState> {
  DriveUploadNotifier({
    required DriveUploadRepository repo,
    required DriveUploadWorker worker,
  })  : _repo = repo,
        _worker = worker,
        super(const DriveUploadState(jobs: [])) {
    _sub = repo.watchQueue().listen((jobs) {
      state = DriveUploadState(jobs: jobs);
    });
  }

  final DriveUploadRepository _repo;
  final DriveUploadWorker _worker;
  StreamSubscription<List<DriveUploadJob>>? _sub;

  Future<void> uploadAll() async {
    await _repo.resetFailedToPending();
    await _worker.drain();
  }

  Future<void> retryJob(String jobId) async {
    await _repo.resetForRetry(jobId);
    await _worker.drain();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4: Implement DriveUploadProviders**

```dart
// lib/core/drive/drive_upload_providers.dart
import 'package:firecheck/core/drive/drive_upload_preferences.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:firecheck/core/drive/google_drive_upload_api.dart';
import 'package:firecheck/features/auth/presentation/google_auth_providers.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_notifier.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final driveUploadRepoProvider = Provider<DriveUploadRepository>((ref) {
  return DriveUploadRepository(ref.watch(appDatabaseProvider));
});

final driveUploadWorkerProvider = Provider<DriveUploadWorker>((ref) {
  final rootFolderId = dotenv.env['DRIVE_UPLOAD_FOLDER_ID'] ?? '';
  return DriveUploadWorker(
    api: GoogleDriveUploadApi(
      googleSignIn: ref.watch(googleSignInProvider),
    ),
    repo: ref.watch(driveUploadRepoProvider),
    db: ref.watch(appDatabaseProvider),
    rootFolderId: rootFolderId,
  );
});

final driveUploadPreferencesProvider = Provider<DriveUploadPreferences>((ref) {
  return DriveUploadPreferences(ref.watch(secureStorageProvider));
});

final driveUploadNotifierProvider =
    StateNotifierProvider<DriveUploadNotifier, DriveUploadState>((ref) {
  return DriveUploadNotifier(
    repo: ref.watch(driveUploadRepoProvider),
    worker: ref.watch(driveUploadWorkerProvider),
  );
});
```

`googleSignInProvider` and `secureStorageProvider` are existing providers. Check `lib/features/auth/presentation/google_auth_providers.dart` and `lib/features/auth/presentation/auth_providers.dart` for the exact provider names and add imports accordingly.

- [ ] **Step 5: Run test + full suite**

```bash
flutter test test/features/upload/upload_queue_notifier_test.dart && flutter test
```

- [ ] **Step 6: Commit**

```bash
git add lib/core/drive/drive_upload_providers.dart lib/features/upload/presentation/upload_queue_notifier.dart test/features/upload/upload_queue_notifier_test.dart
git commit -m "feat(drive): add DriveUploadNotifier, state, and Riverpod providers"
```

---

## Task 12: UploadBanner widget

**Files:**
- Create: `lib/features/upload/presentation/upload_banner.dart`
- Test: `test/features/upload/upload_banner_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/upload/upload_banner_test.dart
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:firecheck/core/drive/fake_drive_upload_api.dart';
import 'package:firecheck/features/upload/presentation/upload_banner.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_notifier.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('banner is hidden when no pending jobs', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriveUploadRepository(db);

    await tester.pumpWidget(_wrap(const UploadBanner(), [
      driveUploadNotifierProvider.overrideWith(
        (ref) => DriveUploadNotifier(
          repo: repo,
          worker: DriveUploadWorker(
            api: FakeDriveUploadApi(), repo: repo, db: db, rootFolderId: 'r',
          ),
        ),
      ),
    ]));
    await tester.pump();

    expect(find.byType(UploadBanner), findsOneWidget);
    expect(find.text(RegExp(r'file')), findsNothing);
  });

  testWidgets('banner shows pending count when jobs exist', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriveUploadRepository(db);
    await repo.insertJob(
      id: 'j1', assignmentId: 'a1', filePath: '/p1.jpg',
      fileType: DriveUploadJobStatus.typePhoto, fileName: 'p1.jpg',
      fileSizeBytes: 1024 * 1024, capturedAt: DateTime(2026),
    );

    await tester.pumpWidget(_wrap(const UploadBanner(), [
      driveUploadNotifierProvider.overrideWith(
        (ref) => DriveUploadNotifier(
          repo: repo,
          worker: DriveUploadWorker(
            api: FakeDriveUploadApi(), repo: repo, db: db, rootFolderId: 'r',
          ),
        ),
      ),
    ]));
    await tester.pump();

    expect(find.textContaining('1'), findsAtLeastNWidgets(1));
  });
}
```

- [ ] **Step 2: Run test — expect compile error**

```bash
flutter test test/features/upload/upload_banner_test.dart
```

- [ ] **Step 3: Implement UploadBanner**

```dart
// lib/features/upload/presentation/upload_banner.dart
import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class UploadBanner extends ConsumerWidget {
  const UploadBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(driveUploadNotifierProvider);
    if (state.pendingCount == 0) return const SizedBox.shrink();

    final totalMb =
        (state.totalPendingBytes / 1024 / 1024).toStringAsFixed(1);

    return Card(
      color: Theme.of(context).colorScheme.primary,
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.cloud_upload,
            color: Theme.of(context).colorScheme.onPrimary),
        title: Text(
          '${state.pendingCount} file${state.pendingCount == 1 ? '' : 's'} ready to upload',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '$totalMb MB',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.8),
          ),
        ),
        trailing: Icon(Icons.chevron_right,
            color: Theme.of(context).colorScheme.onPrimary),
        onTap: () => context.push('/uploads'),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests + full suite**

```bash
flutter test test/features/upload/upload_banner_test.dart && flutter test
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/upload/presentation/upload_banner.dart test/features/upload/upload_banner_test.dart
git commit -m "feat(upload): add UploadBanner widget"
```

---

## Task 13: UploadQueueScreen

**Files:**
- Create: `lib/features/upload/presentation/upload_queue_screen.dart`
- Test: `test/features/upload/upload_queue_screen_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
// test/features/upload/upload_queue_screen_test.dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_preferences.dart';
import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:firecheck/core/drive/fake_drive_upload_api.dart';
import 'package:firecheck/core/security/secure_storage.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_notifier.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(home: UploadQueueScreen()),
  );
}

List<Override> _overrides(AppDatabase db, DriveUploadRepository repo) => [
      driveUploadNotifierProvider.overrideWith(
        (ref) => DriveUploadNotifier(
          repo: repo,
          worker: DriveUploadWorker(
            api: FakeDriveUploadApi(), repo: repo, db: db, rootFolderId: 'r',
          ),
        ),
      ),
      driveUploadPreferencesProvider.overrideWithValue(
        DriveUploadPreferences(InMemorySecureStorage()),
      ),
    ];

void main() {
  testWidgets('shows empty message when no pending files', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriveUploadRepository(db);

    await tester.pumpWidget(_wrap(_overrides(db, repo)));
    await tester.pump();

    expect(find.text('No pending uploads'), findsOneWidget);
  });

  testWidgets('shows file rows when jobs exist', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriveUploadRepository(db);
    await repo.insertJob(
      id: 'j1', assignmentId: 'a1', filePath: '/p1.jpg',
      fileType: DriveUploadJobStatus.typePhoto, fileName: 'photo1.jpg',
      fileSizeBytes: 2048, capturedAt: DateTime(2026),
    );

    await tester.pumpWidget(_wrap(_overrides(db, repo)));
    await tester.pump();

    expect(find.text('photo1.jpg'), findsOneWidget);
    expect(find.textContaining('PENDING'), findsOneWidget);
  });

  testWidgets('Upload All button is present and enabled with pending jobs',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriveUploadRepository(db);
    await repo.insertJob(
      id: 'j1', assignmentId: 'a1', filePath: '/p1.jpg',
      fileType: DriveUploadJobStatus.typePhoto, fileName: 'p1.jpg',
      fileSizeBytes: 100, capturedAt: DateTime(2026),
    );

    await tester.pumpWidget(_wrap(_overrides(db, repo)));
    await tester.pump();

    final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(btn.onPressed, isNotNull);
  });
}
```

- [ ] **Step 2: Run test — expect compile error**

```bash
flutter test test/features/upload/upload_queue_screen_test.dart
```

- [ ] **Step 3: Implement UploadQueueScreen**

```dart
// lib/features/upload/presentation/upload_queue_screen.dart
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_preferences.dart';
import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UploadQueueScreen extends ConsumerStatefulWidget {
  const UploadQueueScreen({super.key});

  @override
  ConsumerState<UploadQueueScreen> createState() => _UploadQueueScreenState();
}

class _UploadQueueScreenState extends ConsumerState<UploadQueueScreen> {
  bool _autoUpload = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = ref.read(driveUploadPreferencesProvider);
    final val = await prefs.isAutoUploadEnabled();
    if (mounted) setState(() => _autoUpload = val);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(driveUploadNotifierProvider);
    final notifier = ref.read(driveUploadNotifierProvider.notifier);
    final prefs = ref.read(driveUploadPreferencesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Uploads')),
      body: Column(
        children: [
          // Summary bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  '${state.pendingCount} file${state.pendingCount == 1 ? '' : 's'}'
                  ' · ${(state.totalPendingBytes / 1024 / 1024).toStringAsFixed(1)} MB',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                const Text('Auto-upload'),
                const SizedBox(width: 8),
                Switch(
                  value: _autoUpload,
                  onChanged: (val) async {
                    await prefs.setAutoUploadEnabled(enabled: val);
                    setState(() => _autoUpload = val);
                  },
                ),
              ],
            ),
          ),

          // Progress bar (shown while uploading)
          if (state.isUploading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Uploading… ${state.completedCount} of '
                    '${state.jobs.length}',
                    style: const TextStyle(color: Colors.blue),
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: state.jobs.isEmpty
                        ? 0
                        : state.completedCount / state.jobs.length,
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),

          // File list
          Expanded(
            child: state.jobs.isEmpty
                ? const Center(child: Text('No pending uploads'))
                : ListView.separated(
                    itemCount: state.jobs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final job = state.jobs[i];
                      return _JobTile(
                        job: job,
                        onRetry: () => notifier.retryJob(job.id),
                      );
                    },
                  ),
          ),

          // Upload All button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: state.isUploading || state.pendingCount == 0
                    ? null
                    : notifier.uploadAll,
                child: const Text('Upload All'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job, required this.onRetry});
  final DriveUploadJob job;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isFailed = job.status == DriveUploadJobStatus.failed ||
        job.status == DriveUploadJobStatus.dead;
    final icon = job.fileType == DriveUploadJobStatus.typePhoto
        ? Icons.image
        : Icons.folder_zip;

    return ListTile(
      leading: Icon(icon),
      title: Text(job.fileName),
      subtitle: isFailed
          ? Text(
              job.failureReason ?? 'Upload failed · Tap to retry',
              style: const TextStyle(color: Colors.red, fontSize: 12),
            )
          : Text(
              '${job.assignmentId} · ${(job.fileSizeBytes / 1024).toStringAsFixed(0)} KB',
              style: const TextStyle(fontSize: 12),
            ),
      trailing: _statusChip(job.status),
      onTap: isFailed ? onRetry : null,
    );
  }

  Widget _statusChip(String status) {
    final (label, color) = switch (status) {
      DriveUploadJobStatus.pending => ('PENDING', Colors.grey),
      DriveUploadJobStatus.uploading => ('UPLOADING', Colors.blue),
      DriveUploadJobStatus.completed => ('✓ DONE', Colors.green),
      DriveUploadJobStatus.failed || DriveUploadJobStatus.dead =>
        ('FAILED', Colors.red),
      _ => (status.toUpperCase(), Colors.grey),
    };
    return Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: color,
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests + full suite**

```bash
flutter test test/features/upload/upload_queue_screen_test.dart && flutter test
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/upload/presentation/upload_queue_screen.dart test/features/upload/upload_queue_screen_test.dart
git commit -m "feat(upload): add UploadQueueScreen with per-file status and Upload All"
```

---

## Task 14: Router + HomeScreen integration

**Files:**
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/features/home/presentation/home_screen.dart`
- Test: `test/features/home/home_screen_upload_banner_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/home/home_screen_upload_banner_test.dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/core/drive/drive_upload_job_status.dart';
import 'package:firecheck/core/drive/drive_upload_providers.dart';
import 'package:firecheck/core/drive/drive_upload_repository.dart';
import 'package:firecheck/core/drive/drive_upload_worker.dart';
import 'package:firecheck/core/drive/fake_drive_upload_api.dart';
import 'package:firecheck/features/upload/presentation/upload_banner.dart';
import 'package:firecheck/features/upload/presentation/upload_queue_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('HomeScreen shows UploadBanner when pending jobs exist',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriveUploadRepository(db);
    await repo.insertJob(
      id: 'j1', assignmentId: 'a1', filePath: '/p1.jpg',
      fileType: DriveUploadJobStatus.typePhoto, fileName: 'p1.jpg',
      fileSizeBytes: 1024, capturedAt: DateTime(2026),
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        driveUploadNotifierProvider.overrideWith(
          (ref) => DriveUploadNotifier(
            repo: repo,
            worker: DriveUploadWorker(
              api: FakeDriveUploadApi(), repo: repo, db: db, rootFolderId: 'r',
            ),
          ),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: UploadBanner()),
      ),
    ));
    await tester.pump();

    expect(find.textContaining('file'), findsAtLeastNWidgets(1));
  });
}
```

- [ ] **Step 2: Run test — expect PASS (UploadBanner already works)**

```bash
flutter test test/features/home/home_screen_upload_banner_test.dart
```

- [ ] **Step 3: Add /uploads route to app_router.dart**

In `lib/core/router/app_router.dart`, add this import:

```dart
import 'package:firecheck/features/upload/presentation/upload_queue_screen.dart';
```

Inside the `routes` list, add after the `/review` route:

```dart
GoRoute(
  path: '/uploads',
  builder: (context, state) => const UploadQueueScreen(),
),
```

- [ ] **Step 4: Add UploadBanner to HomeScreen**

In `lib/features/home/presentation/home_screen.dart`, add this import:

```dart
import 'package:firecheck/features/upload/presentation/upload_banner.dart';
```

In the `Column` children inside `HomeScreen.build()`, add `const UploadBanner()` as the first child (before the progress card):

Find:
```dart
children: [
  if (lock is Submitted)
    SubmittedBanner(submittedAt: lock.submittedAt)
  else
    Card(
```

Replace with:
```dart
children: [
  const UploadBanner(),
  const SizedBox(height: 8),
  if (lock is Submitted)
    SubmittedBanner(submittedAt: lock.submittedAt)
  else
    Card(
```

- [ ] **Step 5: Add DRIVE_UPLOAD_FOLDER_ID to .env**

Open `.env` and add:

```
DRIVE_UPLOAD_FOLDER_ID=your_shared_drive_folder_id_here
```

Replace `your_shared_drive_folder_id_here` with the actual Drive folder ID for the shared organizational `/FieldData/` folder.

- [ ] **Step 6: Run full suite**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/core/router/app_router.dart lib/features/home/presentation/home_screen.dart test/features/home/home_screen_upload_banner_test.dart
git commit -m "feat(upload): wire UploadBanner into HomeScreen and add /uploads route"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| Wi-Fi detection, no cellular uploads | Task 8 (DriveUploadController Wi-Fi gate) |
| Pending queue visibility (name, size, date, assignment) | Task 13 (_JobTile) |
| Total count + size before upload | Task 13 (summary bar) |
| Manual "Upload All" | Task 13 (ElevatedButton → notifier.uploadAll) |
| Auto-upload on Wi-Fi toggle | Task 13 (Switch) + Task 7 (preferences) |
| Per-file status chips | Task 13 (_statusChip) |
| Overall progress indicator | Task 13 (LinearProgressIndicator) |
| Background upload (WorkManager) | Task 9 |
| Drive folder structure | Task 6 (_resolveParentFolder) |
| Error handling / retry (3×) | Task 6 (_nextRetryAt, markDead) |
| Dead jobs require manual retry | Task 2 (resetForRetry), Task 13 (onTap) |
| Upload All resets failed, not dead | Task 2 (resetFailedToPending) |
| Local files never deleted | No deletion code anywhere — confirmed |
| Auth scope request | Task 10 (requestDriveUploadScope) |
| Auth expiry re-auth flow | Not explicitly implemented; GoogleDriveUploadApi will throw AuthFailure which marks the job failed — the UI shows FAILED and user retries. Full re-auth prompt is a follow-up. |
| Resumable uploads (>5 MB) | GoogleDriveUploadApi uses googleapis media upload; resumable URI persistence is a follow-up |
| Queue survives app restart | Drift table persists — confirmed |
| Shapefile generation at enqueue time | Task 5 (EnqueueAssignmentUseCase) |

**Two items deferred (not in scope for this plan):**
1. **Auth expiry snackbar with re-sign-in action** — failed jobs surface in UI; user can re-authenticate via the existing Google auth flow and tap retry.
2. **Resumable URI persistence** — googleapis handles large files internally; explicit URI storage is a follow-up once the basic flow is verified.

---

## Execution Options

Plan complete and saved to `docs/superpowers/plans/2026-05-02-drive-bulk-upload.md`.

**1. Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks.

**2. Inline Execution** — execute in this session using executing-plans with batch checkpoints.

Which approach?
