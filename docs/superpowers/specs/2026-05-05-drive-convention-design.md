# Drive Folder & Filename Convention — Design

**Date:** 2026-05-05
**Story:** US-38 — As an Enumerator, I want the app to enforce the documented Drive folder and filename convention on every upload, so that the supervisor (and any teammate inspecting the bucket) can locate my work without guessing.
**Authority:** Section 2 of `docs/superpowers/specs/2026-05-02-drive-bulk-upload-design.md` is the authoritative convention source.

---

## 1. Problem

The Drive folder hierarchy created by `DriveUploadWorker` already matches the US-29 spec:

```
{rootFolderId}/{enumeratorId}/{YYYY-MM-DD}/photos/
{rootFolderId}/{enumeratorId}/{YYYY-MM-DD}/shapefiles/
```

However, `EnqueueAssignmentUseCase` stores raw basenames in `job.fileName`:
- Photos: `p.basename(photo.localPath)` — e.g., `photo1.jpg` (missing `{assignmentId}_` prefix)
- Shapefiles: `p.basename(zipPath)` — whatever the exporter names the zip

`DriveUploadWorker` passes `job.fileName` directly to the API, so the Drive filename is whatever was stored at enqueue time.

---

## 2. Convention (authoritative)

```
photos/     {assignment_id}_{sanitized_stem}.{ext}
shapefiles/ {assignment_id}.zip
```

---

## 3. Architecture

One new file, two touch points:

```
lib/core/drive/
  drive_filename_formatter.dart     ← NEW: two pure top-level functions
  enqueue_assignment_use_case.dart  ← MODIFIED: call formatter when setting fileName
```

No new providers, classes, or wiring changes. `DriveUploadWorker` is untouched — it already reads `job.fileName` as-is.

---

## 4. Formatter

**File:** `lib/core/drive/drive_filename_formatter.dart`

Two pure top-level functions with no dependencies and no state.

```dart
String formatPhotoFilename(String assignmentId, String originalFilename)
String formatShapefileFilename(String assignmentId)
```

**Sanitization** (applied to the stem of `originalFilename` only, in this order):

1. Extract stem and extension using `package:path` (`basenameWithoutExtension`, `extension`).
2. Replace any character not in `[a-zA-Z0-9_-]` with `_`.
3. Collapse consecutive underscores into one (`__` → `_`).
4. Strip leading and trailing underscores.
5. If the stem is empty after steps 2–4, substitute `file`.
6. Lowercase the extension (stem case is preserved).

**Output format:**
- Photo: `{assignmentId}_{sanitized_stem}.{lowercase_ext}`
- Shapefile: `{assignmentId}.zip`

**Edge case table:**

| Input filename | Sanitized stem | Final (assignmentId = `a1`) |
|---|---|---|
| `photo1.jpg` | `photo1` | `a1_photo1.jpg` |
| `My Photo 2026.jpg` | `My_Photo_2026` | `a1_My_Photo_2026.jpg` |
| `IMG (1) copy.jpeg` | `IMG_1_copy` | `a1_IMG_1_copy.jpeg` |
| `my selfie 😎.jpg` | `my_selfie` | `a1_my_selfie.jpg` |
| `😎.png` | `file` (fallback) | `a1_file.png` |
| `no_extension` | `no_extension` | `a1_no_extension` |
| `PHOTO.JPG` | `PHOTO` | `a1_PHOTO.jpg` |

Filenames are not truncated — Drive supports up to 32,767 characters and UUIDs are 36 chars.

---

## 5. Changes to `EnqueueAssignmentUseCase`

Two lines change:

```dart
// Photos — was: p.basename(photo.localPath)
fileName: formatPhotoFilename(assignmentId, p.basename(photo.localPath)),

// Shapefiles — was: p.basename(zipPath)
fileName: formatShapefileFilename(assignmentId),
```

`filePath` (the local disk path) is untouched. Only `fileName` (what Drive sees) changes.

---

## 6. Error Handling

No new error states. The formatter is pure and always returns a valid non-empty string. All edge cases are handled within the formatter itself (see edge case table above).

---

## 7. Testing

**New:** `test/core/drive/drive_filename_formatter_test.dart`

Pure unit tests — no setup, no mocks. Covers:
- Normal filename (happy path)
- Spaces → underscores
- Special characters stripped
- Emoji-only stem → `file` fallback
- Extension lowercased
- No extension (no dot appended)
- Consecutive underscores collapsed
- `formatShapefileFilename` always returns `{assignmentId}.zip`

**Updated:** `test/core/drive/enqueue_assignment_use_case_test.dart`

Add assertions to the existing `'enqueue creates shapefile job + photo job'` test:

```dart
expect(
  jobs.firstWhere((j) => j.fileType == DriveFileType.photo).fileName,
  equals('a1_photo1.jpg'),
);
expect(
  jobs.firstWhere((j) => j.fileType == DriveFileType.shapefile).fileName,
  equals('a1.zip'),
);
```

---

## 8. Out of Scope

- Changing the Drive folder hierarchy (already correct per US-29 spec)
- Renaming files already uploaded to Drive
- Updating `GoogleDriveApi.uploadAssignmentFiles` (separate older code path, not used by the bulk upload flow)
- Filename deduplication (Drive allows duplicate names in the same folder; not a real risk given the `{assignmentId}` prefix)
