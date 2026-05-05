# US-38 Drive Filename Convention Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce the documented Drive filename convention (`{assignmentId}_{sanitized_stem}.{ext}` for photos, `{assignmentId}.zip` for shapefiles) by applying a pure formatter at enqueue time in `EnqueueAssignmentUseCase`.

**Architecture:** A new `drive_filename_formatter.dart` provides two pure top-level functions with zero dependencies. `EnqueueAssignmentUseCase` calls them when setting `job.fileName`. `DriveUploadWorker` is untouched — it already passes `job.fileName` directly to the API.

**Tech Stack:** Dart, Flutter, `package:path` (already a dependency), `flutter_test`

---

## File Map

| Action | Path |
|---|---|
| Create | `lib/core/drive/drive_filename_formatter.dart` |
| Modify | `lib/core/drive/enqueue_assignment_use_case.dart` (lines 51, 71) |
| Create | `test/core/drive/drive_filename_formatter_test.dart` |
| Modify | `test/core/drive/enqueue_assignment_use_case_test.dart` |

---

## Task 1: Formatter (TDD)

**Files:**
- Create: `lib/core/drive/drive_filename_formatter.dart`
- Create: `test/core/drive/drive_filename_formatter_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/core/drive/drive_filename_formatter_test.dart`:

```dart
import 'package:firecheck/core/drive/drive_filename_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatPhotoFilename', () {
    test('preserves simple alphanumeric filename', () {
      expect(formatPhotoFilename('a1', 'photo1.jpg'), 'a1_photo1.jpg');
    });

    test('replaces spaces with underscores', () {
      expect(formatPhotoFilename('a1', 'My Photo 2026.jpg'), 'a1_My_Photo_2026.jpg');
    });

    test('strips special characters', () {
      expect(formatPhotoFilename('a1', 'IMG (1) copy.jpeg'), 'a1_IMG_1_copy.jpeg');
    });

    test('strips emoji leaving no trailing underscores', () {
      expect(formatPhotoFilename('a1', 'my selfie 😎.jpg'), 'a1_my_selfie.jpg');
    });

    test('emoji-only stem falls back to file', () {
      expect(formatPhotoFilename('a1', '😎.png'), 'a1_file.png');
    });

    test('handles filename with no extension', () {
      expect(formatPhotoFilename('a1', 'no_extension'), 'a1_no_extension');
    });

    test('lowercases the extension', () {
      expect(formatPhotoFilename('a1', 'PHOTO.JPG'), 'a1_PHOTO.jpg');
    });

    test('collapses consecutive underscores from multiple spaces', () {
      expect(formatPhotoFilename('a1', 'a  b.jpg'), 'a1_a_b.jpg');
    });
  });

  group('formatShapefileFilename', () {
    test('returns assignmentId.zip', () {
      expect(formatShapefileFilename('a1'), 'a1.zip');
    });

    test('works with UUID-style assignment IDs', () {
      expect(
        formatShapefileFilename('550e8400-e29b-41d4-a716-446655440000'),
        '550e8400-e29b-41d4-a716-446655440000.zip',
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests — verify they fail**

```bash
flutter test test/core/drive/drive_filename_formatter_test.dart
```

Expected: compile error — `drive_filename_formatter.dart` does not exist yet.

- [ ] **Step 3: Implement the formatter**

Create `lib/core/drive/drive_filename_formatter.dart`:

```dart
import 'package:path/path.dart' as p;

String formatPhotoFilename(String assignmentId, String originalFilename) {
  final ext = p.extension(originalFilename).toLowerCase();
  final stem = p.basenameWithoutExtension(originalFilename);
  final sanitized = _sanitizeStem(stem);
  return '${assignmentId}_$sanitized$ext';
}

String formatShapefileFilename(String assignmentId) => '$assignmentId.zip';

String _sanitizeStem(String stem) {
  var result = stem.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
  result = result.replaceAll(RegExp(r'_+'), '_');
  result = result.replaceAll(RegExp(r'^_+|_+$'), '');
  return result.isEmpty ? 'file' : result;
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
flutter test test/core/drive/drive_filename_formatter_test.dart
```

Expected: 10 tests, all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/drive/drive_filename_formatter.dart \
        test/core/drive/drive_filename_formatter_test.dart
git commit -m "feat(drive): add filename formatter with sanitization (US-38)"
```

---

## Task 2: Wire Formatter into EnqueueAssignmentUseCase (TDD)

**Files:**
- Modify: `test/core/drive/enqueue_assignment_use_case_test.dart`
- Modify: `lib/core/drive/enqueue_assignment_use_case.dart`

- [ ] **Step 1: Add failing filename assertions to the enqueue test**

In `test/core/drive/enqueue_assignment_use_case_test.dart`, the test `'enqueue creates shapefile job + photo job'` currently ends with:

```dart
    expect(count, 2); // 1 shapefile + 1 photo
    final jobs = await repo.getPendingJobs();
    expect(jobs.length, 2);
    expect(jobs.any((j) => j.fileType == DriveFileType.shapefile), isTrue);
    expect(jobs.any((j) => j.fileType == DriveFileType.photo), isTrue);
```

Replace those last four lines with:

```dart
    expect(count, 2); // 1 shapefile + 1 photo
    final jobs = await repo.getPendingJobs();
    expect(jobs.length, 2);
    expect(
      jobs.firstWhere((j) => j.fileType == DriveFileType.photo).fileName,
      equals('a1_photo1.jpg'),
    );
    expect(
      jobs.firstWhere((j) => j.fileType == DriveFileType.shapefile).fileName,
      equals('a1.zip'),
    );
```

The seed data in `_seedDb()` sets the photo's `localPath` to `'${tempDir.path}/photo1.jpg'`, so the formatted photo name must be `a1_photo1.jpg`. The shapefile formatter always returns `{assignmentId}.zip`, so `a1.zip`.

- [ ] **Step 2: Run the test — verify it fails**

```bash
flutter test test/core/drive/enqueue_assignment_use_case_test.dart
```

Expected: FAIL — `fileName` is the raw basename (`photo1.jpg` for the photo, some exporter-generated name for the shapefile).

- [ ] **Step 3: Update EnqueueAssignmentUseCase**

In `lib/core/drive/enqueue_assignment_use_case.dart`, add one import after the existing import block:

```dart
import 'package:firecheck/core/drive/drive_filename_formatter.dart';
```

Then on line 51, change:

```dart
          fileName: p.basename(zipPath),
```

to:

```dart
          fileName: formatShapefileFilename(assignmentId),
```

And on line 71, change:

```dart
        fileName: p.basename(photo.localPath),
```

to:

```dart
        fileName: formatPhotoFilename(assignmentId, p.basename(photo.localPath)),
```

- [ ] **Step 4: Run the tests — verify they pass**

```bash
flutter test test/core/drive/enqueue_assignment_use_case_test.dart
```

Expected: 2 tests, all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/drive/enqueue_assignment_use_case.dart \
        test/core/drive/enqueue_assignment_use_case_test.dart
git commit -m "feat(drive): enforce filename convention at enqueue time (US-38)"
```

---

## Task 3: Regression Check

- [ ] **Step 1: Run the full Drive test suite**

```bash
flutter test test/core/drive/
```

Expected: all tests pass (formatter, enqueue, worker, repository, controller, preferences, types, fake API).

- [ ] **Step 2: Run the full test suite**

```bash
flutter test
```

Expected: all tests pass with no regressions outside the Drive module.
