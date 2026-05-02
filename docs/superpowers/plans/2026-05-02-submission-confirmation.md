# Submission Confirmation with Remote Path Visibility — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent inline confirmation card to the Review screen that shows the Google Drive folder path, reference ID, and timestamp after a successful Drive upload, with a failure/retry card on error.

**Architecture:** A new `DriveUploadNotifier` (StateNotifier) owns the Drive upload lifecycle — idle → in-progress → success/failure — and persists the result to three new nullable columns on `assignments`. The Review screen observes the notifier and renders `DriveUploadConfirmationCard` inline below the existing upload progress bar. On app restart, the notifier reads the stored result from the DB and initialises to `Success` immediately.

**Tech Stack:** Flutter, Drift (SQLite ORM), Riverpod (StateNotifier), googleapis (Google Drive v3), url_launcher (open Drive folder link)

**Spec:** `docs/superpowers/specs/2026-05-02-submission-confirmation-design.md`

**Worktree:** `.worktrees/us-30-submission-confirmation`

---

## File Map

| File | Action |
|---|---|
| `lib/core/db/tables/assignments.dart` | Modify — add 3 columns |
| `lib/core/db/database.dart` | Modify — bump to v9, add migration |
| `lib/features/assignment/data/assignment_repository.dart` | Modify — add `setDriveUploadResult` + `getDriveUploadResult` |
| `test/features/assignment/data/assignment_repository_drive_test.dart` | Create — repository tests |
| `lib/core/drive/drive_api.dart` | Modify — add `uploadAssignmentFiles` to interface |
| `lib/core/drive/fake_drive_api.dart` | Modify — add fake upload implementation |
| `lib/core/drive/google_drive_api.dart` | Modify — implement `uploadAssignmentFiles` |
| `lib/features/review/domain/drive_upload_state.dart` | Create — sealed state class |
| `lib/features/review/presentation/drive_upload_notifier.dart` | Create — StateNotifier |
| `test/features/review/presentation/drive_upload_notifier_test.dart` | Create — notifier tests |
| `lib/features/review/presentation/sections/drive_upload_confirmation_card.dart` | Create — UI widget |
| `test/features/review/presentation/sections/drive_upload_confirmation_card_test.dart` | Create — widget tests |
| `lib/features/review/presentation/review_providers.dart` | Modify — add `driveUploadNotifierProvider` |
| `lib/features/review/presentation/review_screen.dart` | Modify — add confirmation card + Upload to Drive button |
| `pubspec.yaml` | Modify — add `url_launcher` if not present |

---

## Task 1: Drift schema v9 migration

**Files:**
- Modify: `lib/core/db/tables/assignments.dart`
- Modify: `lib/core/db/database.dart`

- [ ] **Step 1.1: Add three nullable columns to the Assignments table**

Open `lib/core/db/tables/assignments.dart`. The file currently ends after `driveFolderId`. Add three new columns before the `primaryKey` override:

```dart
// lib/core/db/tables/assignments.dart
import 'package:drift/drift.dart';

class Assignments extends Table {
  TextColumn get id => text()();
  TextColumn get enumeratorId => text()();
  TextColumn get campaignId => text()();
  TextColumn get boundaryPolygonGeojson => text()();
  DateTimeColumn get downloadedAt => dateTime().nullable()();
  DateTimeColumn get submittedAt => dateTime().nullable()();
  TextColumn get status =>
      text().withDefault(const Constant('assigned'))();
  BoolColumn get closedRemotely => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get driveModifiedTime => text().nullable()();
  TextColumn get driveFolderId => text().nullable()();
  // US-30: Drive upload confirmation
  TextColumn get driveFolderPath => text().nullable()();
  TextColumn get driveFolderUrl => text().nullable()();
  DateTimeColumn get driveUploadConfirmedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 1.2: Bump schema version and add v9 migration in database.dart**

Open `lib/core/db/database.dart`. Change `schemaVersion` from `8` to `9` and add the `if (from < 9)` block inside `onUpgrade`:

```dart
@override
int get schemaVersion => 9;

@override
MigrationStrategy get migration => MigrationStrategy(
  onCreate: (m) async {
    await m.createAll();
  },
  onUpgrade: (m, from, to) async {
    // ... existing if (from < 2) through if (from < 7) blocks unchanged ...
    if (from < 9) {
      // v8 → v9: Drive upload confirmation columns for US-30.
      await m.addColumn(assignments, assignments.driveFolderPath);
      await m.addColumn(assignments, assignments.driveFolderUrl);
      await m.addColumn(assignments, assignments.driveUploadConfirmedAt);
    }
  },
  // ... beforeOpen unchanged ...
);
```

- [ ] **Step 1.3: Regenerate Drift code**

```bash
cd "/Users/johnlesterescarlan/Personal Projects/firecheck/.worktrees/us-30-submission-confirmation"
dart run build_runner build --delete-conflicting-outputs
```

Expected: `database.g.dart` regenerated with no errors. `AssignmentsCompanion` now has `driveFolderPath`, `driveFolderUrl`, `driveUploadConfirmedAt` fields.

- [ ] **Step 1.4: Verify full test suite still passes**

```bash
flutter test
```

Expected: same number of tests passing as before (538 or current count), 0 failures.

- [ ] **Step 1.5: Commit**

```bash
git add lib/core/db/tables/assignments.dart lib/core/db/database.dart lib/core/db/database.g.dart
git commit -m "feat(db): add drive upload confirmation columns — schema v9 (US-30)"
```

---

## Task 2: AssignmentRepository — Drive upload result methods

**Files:**
- Modify: `lib/features/assignment/data/assignment_repository.dart`
- Create: `test/features/assignment/data/assignment_repository_drive_test.dart`

- [ ] **Step 2.1: Write failing tests**

Create `test/features/assignment/data/assignment_repository_drive_test.dart`:

```dart
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

  Future<void> _insertAssignment() async {
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
      await _insertAssignment();
      expect(await repo.getDriveUploadResult(assignmentId), isNull);
    });

    test('returns null when assignment does not exist', () async {
      expect(await repo.getDriveUploadResult('nonexistent'), isNull);
    });
  });

  group('setDriveUploadResult + getDriveUploadResult', () {
    test('round-trips all three values', () async {
      await _insertAssignment();
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
      await _insertAssignment();
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
  });
}
```

- [ ] **Step 2.2: Run tests to confirm they fail**

```bash
flutter test test/features/assignment/data/assignment_repository_drive_test.dart -v
```

Expected: FAIL — `The method 'setDriveUploadResult' isn't defined` (or similar).

- [ ] **Step 2.3: Add the two methods to AssignmentRepository**

Open `lib/features/assignment/data/assignment_repository.dart` and add after the existing `watchCurrentAssignment()` method:

```dart
Future<void> setDriveUploadResult({
  required String assignmentId,
  required String driveFolderPath,
  required String driveFolderUrl,
  required DateTime driveUploadConfirmedAt,
}) async {
  await (db.update(db.assignments)
        ..where((t) => t.id.equals(assignmentId)))
      .write(AssignmentsCompanion(
        driveFolderPath: Value(driveFolderPath),
        driveFolderUrl: Value(driveFolderUrl),
        driveUploadConfirmedAt: Value(driveUploadConfirmedAt),
      ));
}

Future<({String folderPath, String folderUrl, DateTime confirmedAt})?> getDriveUploadResult(
  String assignmentId,
) async {
  final row = await (db.select(db.assignments)
        ..where((t) => t.id.equals(assignmentId)))
      .getSingleOrNull();
  if (row == null ||
      row.driveFolderPath == null ||
      row.driveFolderUrl == null ||
      row.driveUploadConfirmedAt == null) return null;
  return (
    folderPath: row.driveFolderPath!,
    folderUrl: row.driveFolderUrl!,
    confirmedAt: row.driveUploadConfirmedAt!,
  );
}
```

- [ ] **Step 2.4: Run tests to confirm they pass**

```bash
flutter test test/features/assignment/data/assignment_repository_drive_test.dart -v
```

Expected: 4 tests, all PASS.

- [ ] **Step 2.5: Run full suite**

```bash
flutter test
```

Expected: 0 failures.

- [ ] **Step 2.6: Commit**

```bash
git add lib/features/assignment/data/assignment_repository.dart \
        test/features/assignment/data/assignment_repository_drive_test.dart
git commit -m "feat(assignment): add setDriveUploadResult and getDriveUploadResult (US-30)"
```

---

## Task 3: DriveApi interface + FakeDriveApi — uploadAssignmentFiles

**Files:**
- Modify: `lib/core/drive/drive_api.dart`
- Modify: `lib/core/drive/fake_drive_api.dart`

- [ ] **Step 3.1: Add uploadAssignmentFiles to the DriveApi interface**

Open `lib/core/drive/drive_api.dart`. Add the import and the method:

```dart
import 'dart:typed_data';

import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';

abstract interface class DriveApi {
  Future<List<DriveAssignment>> listAssignments();
  Future<int> getTotalSize(String assignmentId);
  Stream<DriveDownloadEvent> downloadShapefiles(String assignmentId);

  /// Uploads [files] to FieldData/{enumeratorId}/{YYYY-MM-DD}/ on Drive.
  /// Returns the folder's human-readable path and its full Drive URL.
  Future<({String folderPath, String folderUrl})> uploadAssignmentFiles({
    required String enumeratorId,
    required String assignmentId,
    required List<({String filename, Uint8List bytes})> files,
  });
}
```

- [ ] **Step 3.2: Add upload support to FakeDriveApi**

Open `lib/core/drive/fake_drive_api.dart`. Replace the entire file:

```dart
import 'dart:typed_data';
import 'package:firecheck/core/drive/drive_api.dart';
import 'package:firecheck/core/drive/drive_assignment.dart';
import 'package:firecheck/core/drive/drive_download_event.dart';

class FakeDriveApi implements DriveApi {
  FakeDriveApi({
    List<DriveAssignment>? assignments,
    int totalSize = 1024,
    Map<String, Uint8List>? downloadComplete,
    Map<String, String>? expectedMd5s,
    List<DriveDownloadEvent>? downloadEvents,
    Exception? listError,
    Exception? downloadError,
    Exception? uploadError,
    ({String folderPath, String folderUrl})? uploadResult,
  })  : _assignments = assignments ?? [],
        _totalSize = totalSize,
        _downloadComplete = downloadComplete,
        _expectedMd5s = expectedMd5s ?? {},
        _downloadEvents = downloadEvents,
        _listError = listError,
        _downloadError = downloadError,
        _uploadError = uploadError,
        _uploadResult = uploadResult;

  final List<DriveAssignment> _assignments;
  final int _totalSize;
  final Map<String, Uint8List>? _downloadComplete;
  final Map<String, String> _expectedMd5s;
  final List<DriveDownloadEvent>? _downloadEvents;
  final Exception? _listError;
  final Exception? _downloadError;
  final Exception? _uploadError;
  final ({String folderPath, String folderUrl})? _uploadResult;

  @override
  Future<List<DriveAssignment>> listAssignments() async {
    if (_listError != null) throw _listError;
    return List.unmodifiable(_assignments);
  }

  @override
  Future<int> getTotalSize(String assignmentId) async {
    assert(
      _assignments.any((a) => a.assignmentId == assignmentId),
      'FakeDriveApi: unknown assignmentId "$assignmentId"',
    );
    return _totalSize;
  }

  @override
  Stream<DriveDownloadEvent> downloadShapefiles(String assignmentId) async* {
    assert(
      _assignments.any((a) => a.assignmentId == assignmentId),
      'FakeDriveApi: unknown assignmentId "$assignmentId"',
    );
    if (_downloadError != null) throw _downloadError;
    if (_downloadEvents != null) {
      for (final e in _downloadEvents) {
        yield e;
      }
      return;
    }
    yield DriveDownloadComplete(_downloadComplete ?? {}, _expectedMd5s);
  }

  @override
  Future<({String folderPath, String folderUrl})> uploadAssignmentFiles({
    required String enumeratorId,
    required String assignmentId,
    required List<({String filename, Uint8List bytes})> files,
  }) async {
    if (_uploadError != null) throw _uploadError;
    return _uploadResult ??
        (
          folderPath: 'FieldData/$enumeratorId/2026-05-02/',
          folderUrl: 'https://drive.google.com/drive/folders/fake-folder-id',
        );
  }
}
```

- [ ] **Step 3.3: Verify full suite still passes**

```bash
flutter test
```

Expected: 0 failures. (No existing tests break — FakeDriveApi is backwards-compatible.)

- [ ] **Step 3.4: Commit**

```bash
git add lib/core/drive/drive_api.dart lib/core/drive/fake_drive_api.dart
git commit -m "feat(drive): add uploadAssignmentFiles to DriveApi interface and FakeDriveApi (US-30)"
```

---

## Task 4: GoogleDriveApi — implement uploadAssignmentFiles

**Files:**
- Modify: `lib/core/drive/google_drive_api.dart`

- [ ] **Step 4.1: Implement uploadAssignmentFiles in GoogleDriveApi**

Open `lib/core/drive/google_drive_api.dart`. Add the method at the end of the class, before the closing `}`:

```dart
@override
Future<({String folderPath, String folderUrl})> uploadAssignmentFiles({
  required String enumeratorId,
  required String assignmentId,
  required List<({String filename, Uint8List bytes})> files,
}) async {
  final api = await _api();
  final now = DateTime.now();
  final date =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

  final fieldDataId = await _findOrCreateFolder(api, null, 'FieldData');
  final enumeratorFolderId =
      await _findOrCreateFolder(api, fieldDataId, enumeratorId);
  final dateFolderId =
      await _findOrCreateFolder(api, enumeratorFolderId, date);

  for (final file in files) {
    final media = gdrive.Media(
      Stream.value(file.bytes),
      file.bytes.length,
    );
    await api.files.create(
      gdrive.File()
        ..name = file.filename
        ..parents = [dateFolderId],
      uploadMedia: media,
    );
  }

  return (
    folderPath: 'FieldData/$enumeratorId/$date/',
    folderUrl: 'https://drive.google.com/drive/folders/$dateFolderId',
  );
}

Future<String> _findOrCreateFolder(
  gdrive.DriveApi api,
  String? parentId,
  String name,
) async {
  final escapedName = name.replaceAll("'", "\\'");
  final parentClause =
      parentId != null ? " and '$parentId' in parents" : '';
  final result = await api.files.list(
    q: "name = '$escapedName'"
        " and mimeType = 'application/vnd.google-apps.folder'"
        " and trashed = false"
        '$parentClause',
    spaces: 'drive',
    \$fields: 'files(id)',
  );
  if (result.files?.isNotEmpty == true) {
    return result.files!.first.id!;
  }
  final folder = await api.files.create(
    gdrive.File()
      ..name = name
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = parentId != null ? [parentId] : null,
  );
  return folder.id!;
}
```

- [ ] **Step 4.2: Run full suite**

```bash
flutter test
```

Expected: 0 failures.

- [ ] **Step 4.3: Commit**

```bash
git add lib/core/drive/google_drive_api.dart
git commit -m "feat(drive): implement uploadAssignmentFiles in GoogleDriveApi (US-30)"
```

---

## Task 5: DriveUploadState sealed class

**Files:**
- Create: `lib/features/review/domain/drive_upload_state.dart`

- [ ] **Step 5.1: Create the sealed state class**

Create `lib/features/review/domain/drive_upload_state.dart`:

```dart
import 'package:flutter/foundation.dart';

sealed class DriveUploadState {
  const DriveUploadState();
}

@immutable
class DriveUploadIdle extends DriveUploadState {
  const DriveUploadIdle();
}

@immutable
class DriveUploadInProgress extends DriveUploadState {
  const DriveUploadInProgress(this.progress);
  final double progress; // 0.0–1.0

  @override
  bool operator ==(Object other) =>
      other is DriveUploadInProgress && other.progress == progress;
  @override
  int get hashCode => progress.hashCode;
}

@immutable
class DriveUploadSuccess extends DriveUploadState {
  const DriveUploadSuccess({
    required this.folderPath,
    required this.folderUrl,
    required this.referenceId,
    required this.confirmedAt,
  });
  final String folderPath;
  final String folderUrl;
  final String referenceId;
  final DateTime confirmedAt;

  @override
  bool operator ==(Object other) =>
      other is DriveUploadSuccess &&
      other.folderPath == folderPath &&
      other.folderUrl == folderUrl &&
      other.referenceId == referenceId &&
      other.confirmedAt == confirmedAt;
  @override
  int get hashCode =>
      Object.hash(folderPath, folderUrl, referenceId, confirmedAt);
}

@immutable
class DriveUploadFailure extends DriveUploadState {
  const DriveUploadFailure({required this.message, required this.canRetry});
  final String message;
  final bool canRetry;

  @override
  bool operator ==(Object other) =>
      other is DriveUploadFailure &&
      other.message == message &&
      other.canRetry == canRetry;
  @override
  int get hashCode => Object.hash(message, canRetry);
}
```

- [ ] **Step 5.2: Run full suite**

```bash
flutter test
```

Expected: 0 failures.

- [ ] **Step 5.3: Commit**

```bash
git add lib/features/review/domain/drive_upload_state.dart
git commit -m "feat(review): add DriveUploadState sealed class (US-30)"
```

---

## Task 6: DriveUploadNotifier + Riverpod provider

**Files:**
- Create: `lib/features/review/presentation/drive_upload_notifier.dart`
- Modify: `lib/features/review/presentation/review_providers.dart`
- Create: `test/features/review/presentation/drive_upload_notifier_test.dart`

- [ ] **Step 6.1: Write failing tests**

Create `test/features/review/presentation/drive_upload_notifier_test.dart`:

```dart
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

  DriveUploadNotifier _notifier({
    FakeDriveApi? driveApi,
  }) =>
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
    test('happy path: Idle → InProgress → Success and writes to DB', () async {
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
        driveApi: FakeDriveApi(
          uploadError: Exception('Network error'),
        ),
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
          uploadError: const AuthFailure('Not signed in'),
        ),
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
      // Force failure state
      n.debugSetState(const DriveUploadFailure(message: 'err', canRetry: true));
      await n.retry(emptyFiles);

      expect(n.state, isA<DriveUploadSuccess>());
    });
  });
}
```

- [ ] **Step 6.2: Run tests to confirm they fail**

```bash
flutter test test/features/review/presentation/drive_upload_notifier_test.dart -v
```

Expected: FAIL — `DriveUploadNotifier` not found.

- [ ] **Step 6.3: Create DriveUploadNotifier**

Create `lib/features/review/presentation/drive_upload_notifier.dart`:

```dart
import 'dart:typed_data';

import 'package:firecheck/core/drive/drive_api.dart';
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/assignment/data/assignment_repository.dart';
import 'package:firecheck/features/review/domain/drive_upload_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DriveUploadNotifier extends StateNotifier<DriveUploadState> {
  DriveUploadNotifier({
    required DriveApi driveApi,
    required AssignmentRepository assignmentRepository,
  })  : _driveApi = driveApi,
        _assignmentRepository = assignmentRepository,
        super(const DriveUploadIdle());

  final DriveApi _driveApi;
  final AssignmentRepository _assignmentRepository;
  String? _assignmentId;
  String? _enumeratorId;

  String _formatReferenceId(String id) =>
      'ASN-${id.substring(0, 8).toUpperCase()}';

  /// Reads persisted Drive upload result from DB. Call once after construction.
  /// Transitions to [DriveUploadSuccess] if a prior result is stored.
  Future<void> initFromDb(String assignmentId, String enumeratorId) async {
    _assignmentId = assignmentId;
    _enumeratorId = enumeratorId;
    final result = await _assignmentRepository.getDriveUploadResult(assignmentId);
    if (!mounted) return;
    if (result != null) {
      state = DriveUploadSuccess(
        folderPath: result.folderPath,
        folderUrl: result.folderUrl,
        referenceId: _formatReferenceId(assignmentId),
        confirmedAt: result.confirmedAt,
      );
    }
  }

  Future<void> startUpload(List<({String filename, Uint8List bytes})> files) async {
    final assignmentId = _assignmentId;
    final enumeratorId = _enumeratorId;
    if (assignmentId == null || enumeratorId == null) return;

    state = const DriveUploadInProgress(0.0);
    try {
      final result = await _driveApi.uploadAssignmentFiles(
        enumeratorId: enumeratorId,
        assignmentId: assignmentId,
        files: files,
      );
      final confirmedAt = DateTime.now();
      await _assignmentRepository.setDriveUploadResult(
        assignmentId: assignmentId,
        driveFolderPath: result.folderPath,
        driveFolderUrl: result.folderUrl,
        driveUploadConfirmedAt: confirmedAt,
      );
      if (!mounted) return;
      state = DriveUploadSuccess(
        folderPath: result.folderPath,
        folderUrl: result.folderUrl,
        referenceId: _formatReferenceId(assignmentId),
        confirmedAt: confirmedAt,
      );
    } on AuthFailure {
      if (!mounted) return;
      state = const DriveUploadFailure(
        message:
            'Google Drive authentication expired. Please sign in again.',
        canRetry: false,
      );
    } catch (_) {
      if (!mounted) return;
      state = DriveUploadFailure(
        message:
            'Could not reach Google Drive. Check your Wi-Fi and try again.',
        canRetry: true,
      );
    }
  }

  Future<void> retry(List<({String filename, Uint8List bytes})> files) async {
    state = const DriveUploadIdle();
    await startUpload(files);
  }

  /// Test-only: force a specific state for retry tests.
  void debugSetState(DriveUploadState s) => state = s;
}
```

- [ ] **Step 6.4: Run notifier tests**

```bash
flutter test test/features/review/presentation/drive_upload_notifier_test.dart -v
```

Expected: 5 tests, all PASS.

- [ ] **Step 6.5: Add driveUploadNotifierProvider to review_providers.dart**

Open `lib/features/review/presentation/review_providers.dart`. Add these imports at the top:

```dart
import 'package:firecheck/core/drive/drive_api.dart';
import 'package:firecheck/features/review/domain/drive_upload_state.dart';
import 'package:firecheck/features/review/presentation/drive_upload_notifier.dart';
```

Then find the `driveApiProvider`. If it does not exist anywhere in `lib/`, add it at the top of the providers block (before `reviewRepositoryProvider`):

```dart
// Provide the concrete DriveApi implementation.
// Replace FakeDriveApi with GoogleDriveApi(googleSignIn: ...) for production.
final driveApiProvider = Provider<DriveApi>((ref) => FakeDriveApi());
```

*(If a `driveApiProvider` already exists in another file, import it instead of declaring a duplicate.)*

Then add the notifier provider at the bottom of the file:

```dart
final driveUploadNotifierProvider =
    StateNotifierProvider<DriveUploadNotifier, DriveUploadState>((ref) {
  final notifier = DriveUploadNotifier(
    driveApi: ref.watch(driveApiProvider),
    assignmentRepository: ref.watch(assignmentRepositoryProvider),
  );
  ref
      .watch(assignmentRepositoryProvider)
      .getCurrentAssignment()
      .then((assignment) {
    if (assignment != null) {
      notifier.initFromDb(assignment.id, assignment.enumeratorId);
    }
  });
  return notifier;
});
```

- [ ] **Step 6.6: Add FakeDriveApi import to review_providers.dart if needed**

If you added `driveApiProvider` pointing to `FakeDriveApi`, add this import:

```dart
import 'package:firecheck/core/drive/fake_drive_api.dart';
```

- [ ] **Step 6.7: Run full suite**

```bash
flutter test
```

Expected: 0 failures.

- [ ] **Step 6.8: Commit**

```bash
git add lib/features/review/presentation/drive_upload_notifier.dart \
        lib/features/review/presentation/review_providers.dart \
        test/features/review/presentation/drive_upload_notifier_test.dart
git commit -m "feat(review): add DriveUploadNotifier and provider (US-30)"
```

---

## Task 7: DriveUploadConfirmationCard widget + tests

**Files:**
- Modify: `pubspec.yaml` (add url_launcher if missing)
- Create: `lib/features/review/presentation/sections/drive_upload_confirmation_card.dart`
- Create: `test/features/review/presentation/sections/drive_upload_confirmation_card_test.dart`

- [ ] **Step 7.1: Add url_launcher if not already a dependency**

Check `pubspec.yaml` for `url_launcher`. If absent, add it under `dependencies`:

```yaml
dependencies:
  url_launcher: ^6.3.0
```

Then run:

```bash
flutter pub get
```

- [ ] **Step 7.2: Write failing widget tests**

Create `test/features/review/presentation/sections/drive_upload_confirmation_card_test.dart`:

```dart
import 'package:firecheck/features/review/domain/drive_upload_state.dart';
import 'package:firecheck/features/review/presentation/sections/drive_upload_confirmation_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final successState = DriveUploadSuccess(
    folderPath: 'FieldData/enum-1/2026-05-02/',
    folderUrl: 'https://drive.google.com/drive/folders/abc123',
    referenceId: 'ASN-AABBCCDD',
    confirmedAt: DateTime(2026, 5, 2, 20, 42),
  );

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('renders nothing when Idle', (tester) async {
    await tester.pumpWidget(wrap(
      DriveUploadConfirmationCard(state: const DriveUploadIdle()),
    ));
    expect(find.text('Submitted to Google Drive'), findsNothing);
    expect(find.text('Upload Failed'), findsNothing);
  });

  testWidgets('renders nothing when InProgress', (tester) async {
    await tester.pumpWidget(wrap(
      DriveUploadConfirmationCard(state: const DriveUploadInProgress(0.5)),
    ));
    expect(find.text('Submitted to Google Drive'), findsNothing);
  });

  testWidgets('success state renders path, reference ID, and timestamp', (tester) async {
    await tester.pumpWidget(wrap(
      DriveUploadConfirmationCard(state: successState),
    ));

    expect(find.text('Submitted to Google Drive'), findsOneWidget);
    expect(find.text('FieldData/enum-1/2026-05-02/'), findsOneWidget);
    expect(find.text('ASN-AABBCCDD'), findsOneWidget);
    expect(find.text('Open in Google Drive →'), findsOneWidget);
  });

  testWidgets('Copy button copies full Drive URL to clipboard', (tester) async {
    final log = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        log.add(call);
        return null;
      },
    );

    await tester.pumpWidget(wrap(
      DriveUploadConfirmationCard(state: successState),
    ));

    await tester.tap(find.text('Copy'));
    await tester.pump();

    expect(
      log.any((c) =>
          c.method == 'Clipboard.setData' &&
          (c.arguments as Map)['text'] ==
              'https://drive.google.com/drive/folders/abc123'),
      isTrue,
    );
  });

  testWidgets('failure state renders error message and retry button', (tester) async {
    bool retryCalled = false;
    await tester.pumpWidget(wrap(
      DriveUploadConfirmationCard(
        state: const DriveUploadFailure(
          message: 'Could not reach Google Drive.',
          canRetry: true,
        ),
        onRetry: () => retryCalled = true,
      ),
    ));

    expect(find.text('Upload Failed'), findsOneWidget);
    expect(find.text('Could not reach Google Drive.'), findsOneWidget);
    expect(find.text('Retry Upload'), findsOneWidget);
    expect(find.text('Submitted to Google Drive'), findsNothing);

    await tester.tap(find.text('Retry Upload'));
    expect(retryCalled, isTrue);
  });

  testWidgets('auth failure shows Re-authenticate button instead of Retry', (tester) async {
    await tester.pumpWidget(wrap(
      DriveUploadConfirmationCard(
        state: const DriveUploadFailure(
          message: 'Google Drive authentication expired.',
          canRetry: false,
        ),
      ),
    ));

    expect(find.text('Re-authenticate'), findsOneWidget);
    expect(find.text('Retry Upload'), findsNothing);
  });
}
```

- [ ] **Step 7.3: Run tests to confirm they fail**

```bash
flutter test test/features/review/presentation/sections/drive_upload_confirmation_card_test.dart -v
```

Expected: FAIL — `DriveUploadConfirmationCard` not found.

- [ ] **Step 7.4: Create the DriveUploadConfirmationCard widget**

Create `lib/features/review/presentation/sections/drive_upload_confirmation_card.dart`:

```dart
import 'package:firecheck/features/review/domain/drive_upload_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class DriveUploadConfirmationCard extends StatelessWidget {
  const DriveUploadConfirmationCard({
    required this.state,
    this.onRetry,
    super.key,
  });

  final DriveUploadState state;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      DriveUploadIdle() || DriveUploadInProgress() => const SizedBox.shrink(),
      DriveUploadSuccess(
        :final folderPath,
        :final folderUrl,
        :final referenceId,
        :final confirmedAt,
      ) =>
        _SuccessCard(
          folderPath: folderPath,
          folderUrl: folderUrl,
          referenceId: referenceId,
          confirmedAt: confirmedAt,
        ),
      DriveUploadFailure(:final message, :final canRetry) => _FailureCard(
          message: message,
          canRetry: canRetry,
          onRetry: onRetry,
        ),
    };
  }
}

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({
    required this.folderPath,
    required this.folderUrl,
    required this.referenceId,
    required this.confirmedAt,
  });

  final String folderPath;
  final String folderUrl;
  final String referenceId;
  final DateTime confirmedAt;

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = dt.hour > 12
        ? dt.hour - 12
        : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day} · $h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Upload successful. Remote path: $folderPath. Reference ID: $referenceId.',
      excludeSemantics: true,
      child: Card(
        color: const Color(0xFFF0FDF4),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFF16A34A), width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Color(0xFF15803D), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Submitted to Google Drive',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF15803D),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'REMOTE PATH',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF166534),
                        letterSpacing: 0.06,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            folderPath,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Color(0xFF14532D),
                            ),
                          ),
                        ),
                        Semantics(
                          label: 'Copy remote path to clipboard',
                          child: TextButton(
                            onPressed: () => Clipboard.setData(
                              ClipboardData(text: folderUrl),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              backgroundColor: const Color(0xFF16A34A),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text(
                              'Copy',
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _InfoBox(label: 'REFERENCE ID', value: referenceId),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _InfoBox(
                      label: 'CONFIRMED',
                      value: _formatDate(confirmedAt),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => launchUrl(Uri.parse(folderUrl)),
                child: const Center(
                  child: Text(
                    'Open in Google Drive →',
                    style: TextStyle(
                      color: Color(0xFF16A34A),
                      fontSize: 12,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Color(0xFF166534),
              letterSpacing: 0.06,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF14532D),
            ),
          ),
        ],
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({
    required this.message,
    required this.canRetry,
    this.onRetry,
  });

  final String message;
  final bool canRetry;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Upload failed. $message.${canRetry ? ' Retry button available.' : ''}',
      excludeSemantics: true,
      child: Card(
        color: const Color(0xFFFEF2F2),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.error, color: Color(0xFFDC2626), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Upload Failed',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(
                  color: Color(0xFF7F1D1D),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canRetry ? onRetry : onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(canRetry ? 'Retry Upload' : 'Re-authenticate'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7.5: Run widget tests**

```bash
flutter test test/features/review/presentation/sections/drive_upload_confirmation_card_test.dart -v
```

Expected: 5 tests, all PASS.

- [ ] **Step 7.6: Run full suite**

```bash
flutter test
```

Expected: 0 failures.

- [ ] **Step 7.7: Commit**

```bash
git add pubspec.yaml pubspec.lock \
        lib/features/review/presentation/sections/drive_upload_confirmation_card.dart \
        test/features/review/presentation/sections/drive_upload_confirmation_card_test.dart
git commit -m "feat(review): add DriveUploadConfirmationCard widget (US-30)"
```

---

## Task 8: Wire Review screen — Upload to Drive button + confirmation card

**Files:**
- Modify: `lib/features/review/presentation/review_screen.dart`

- [ ] **Step 8.1: Add DriveUploadConfirmationCard and Upload to Drive button to ReviewScreen**

Open `lib/features/review/presentation/review_screen.dart`. Replace the entire file with:

```dart
import 'package:firecheck/features/assignment/presentation/assignment_providers.dart';
import 'package:firecheck/features/review/domain/drive_upload_state.dart';
import 'package:firecheck/features/review/domain/review_state.dart';
import 'package:firecheck/features/review/domain/upload_progress.dart';
import 'package:firecheck/features/review/presentation/drive_upload_notifier.dart';
import 'package:firecheck/features/review/presentation/review_providers.dart';
import 'package:firecheck/features/review/presentation/sections/drive_upload_confirmation_card.dart';
import 'package:firecheck/features/review/presentation/sections/failed_jobs_section.dart';
import 'package:firecheck/features/review/presentation/sections/start_upload_button.dart';
import 'package:firecheck/features/review/presentation/sections/summary_card.dart';
import 'package:firecheck/features/review/presentation/sections/upload_progress_section.dart';
import 'package:firecheck/features/review/presentation/sections/validation_section.dart';
import 'package:firecheck/generated/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final stateAsync = ref.watch(reviewStateProvider);
    final driveUpload = ref.watch(driveUploadNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.reviewTitle)),
      body: stateAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (state) {
          final inProgressOrCompleted =
              state.upload is InProgress || state.upload is Completed;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (inProgressOrCompleted)
                UploadProgressSection(progress: state.upload)
              else ...[
                SummaryCard(summary: state.summary),
                const SizedBox(height: 8),
                FailedJobsSection(
                  deadJobs: state.deadJobs,
                  onRetryAll: () =>
                      ref.read(retryDeadUseCaseProvider).retryAll(),
                  onRetryOne: (id) =>
                      ref.read(retryDeadUseCaseProvider).retryOne(id),
                ),
                const SizedBox(height: 8),
                ValidationSection(
                  issues: state.blockers,
                  severity: ReviewSeverity.blocker,
                  onGoToFeature: (id) =>
                      context.go('/feature/${Uri.encodeComponent(id)}'),
                ),
                const SizedBox(height: 8),
                ValidationSection(
                  issues: state.warnings,
                  severity: ReviewSeverity.warning,
                  onGoToFeature: (id) =>
                      context.go('/feature/${Uri.encodeComponent(id)}'),
                ),
                const SizedBox(height: 16),
                StartUploadButton(
                  enabled: state.canStartUpload,
                  onPressed: () => _startSupabaseUpload(context, ref),
                ),
                const SizedBox(height: 8),
                if (driveUpload is! DriveUploadSuccess) ...[
                  FilledButton.icon(
                    onPressed: driveUpload is DriveUploadInProgress
                        ? null
                        : () => _startDriveUpload(ref),
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Upload to Google Drive'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1A73E8),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                DriveUploadConfirmationCard(
                  state: driveUpload,
                  onRetry: () => _startDriveUpload(ref),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _startSupabaseUpload(BuildContext context, WidgetRef ref) async {
    ref.read(uploadProgressControllerProvider.notifier).beginUpload();
    final useCase = ref.read(startUploadUseCaseProvider);
    final repo = ref.read(assignmentRepositoryProvider);
    final assignment = await repo.getCurrentAssignment();
    if (assignment == null) return;
    await useCase.execute(assignment.id);
  }

  Future<void> _startDriveUpload(WidgetRef ref) async {
    // Files list is populated by US-29. For now, uploads with empty list
    // to validate the confirmation flow end-to-end.
    await ref
        .read(driveUploadNotifierProvider.notifier)
        .startUpload([]);
  }
}
```

- [ ] **Step 8.2: Run full suite**

```bash
flutter test
```

Expected: 0 failures.

- [ ] **Step 8.3: Commit**

```bash
git add lib/features/review/presentation/review_screen.dart
git commit -m "feat(review): wire DriveUploadConfirmationCard and Upload to Drive button (US-30)"
```

---

## Done

All tasks complete. Run `flutter test` one final time to confirm the full suite is green, then push the branch and open a PR against `main`.

```bash
flutter test
git push origin 30-as-an-enumerator-i-want-a-clear-confirmation-including-the-remote-path-so-that-i-know-the-work-is-delivered
```
