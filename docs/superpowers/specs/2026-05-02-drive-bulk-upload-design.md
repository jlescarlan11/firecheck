# Drive Bulk Upload Design

**Date:** 2026-05-02
**Story:** US-29 — As an Enumerator, I want to upload my completed photos and shapefiles to Google Drive when I have a Wi-Fi connection, so that my supervisor can review them in one place.

---

## 1. Architecture

Seven components in three layers:

```
UI Layer
  HomeScreen (pending banner)  →  UploadQueueScreen

Domain Layer
  DriveUploadNotifier (Riverpod)
  CompleteAssignmentUseCase       — triggers queue population on assignment completion

Infrastructure Layer
  DriveUploadRepository           — Drift CRUD over DriveUploadJobs table
  DriveUploadWorker               — processes queue, retries, calls DriveApi
  DriveUploadJobs (Drift table)   — persistent upload queue
  DriveApi (extended)             — adds uploadFile() and createFolder()
  ShapefileExporter (existing)    — called by CompleteAssignmentUseCase
  connectivity_plus (existing)    — Wi-Fi detection
  WorkManager (existing)          — periodic background tick
```

**Happy-path data flow:**

1. Enumerator completes assignment → `CompleteAssignmentUseCase` calls `ShapefileExporter` to generate a ZIP, then writes one `DriveUploadJob` row per photo and one for the shapefile ZIP.
2. `DriveUploadWorker` picks up `pending` jobs — triggered by Wi-Fi connect (if auto-upload is on) or manually via "Upload All".
3. Worker calls `DriveApi.uploadFile()`. Files >5 MB use a resumable session; the session URI is stored in `resumable_uri` before streaming begins so interrupted uploads resume rather than restart.
4. On success: `status = completed`, `drive_file_id` recorded, `resumable_uri` cleared.
5. On transient failure: `retry_count` incremented, `next_retry_at` set, `status = failed`.
6. After 3 failures: `status = dead`, `failure_reason` recorded.
7. `DriveUploadNotifier` watches the table via Drift stream and updates UI in real time.

---

## 2. Data Model

### `DriveUploadJobs` Drift table

| Column | Type | Notes |
|---|---|---|
| `id` | `TextColumn` | UUID primary key |
| `assignment_id` | `TextColumn` | FK to Assignments |
| `file_path` | `TextColumn` | Absolute path on device |
| `file_type` | `TextColumn` | `photo` or `shapefile` |
| `file_name` | `TextColumn` | Display name |
| `file_size_bytes` | `IntColumn` | Used for queue summary |
| `captured_at` | `DateTimeColumn` | Photo EXIF date or shapefile export time |
| `status` | `TextColumn` | `pending` \| `uploading` \| `completed` \| `failed` \| `dead` |
| `resumable_uri` | `TextColumn?` | Drive resumable upload session URI |
| `drive_file_id` | `TextColumn?` | Drive file ID after success |
| `retry_count` | `IntColumn` | Default 0 |
| `failure_reason` | `TextColumn?` | Last error message |
| `next_retry_at` | `DateTimeColumn?` | Null until first failure |
| `created_at` | `DateTimeColumn` | When job was enqueued |

### Drive folder structure

```
/FieldData/
  {enumerator_id}/
    {YYYY-MM-DD}/
      photos/
        {assignment_id}_{filename}.jpg
      shapefiles/
        {assignment_id}.zip
```

The root folder ID (`/FieldData/`) is stored in `.env` as `DRIVE_UPLOAD_FOLDER_ID`. Before each upload, the worker resolves subfolder IDs by querying Drive for existing folders with the expected name/parent; it creates them if missing. Resolved IDs are cached in memory for the lifetime of the worker run (not persisted — Drive API calls are cheap and idempotent).

### Preferences

Stored in `flutter_secure_storage`:
- `drive_auto_upload_enabled` — `"true"` / `"false"`, default `"false"`

---

## 3. Upload Pipeline

### `DriveUploadWorker`

- Processes up to 3 concurrent uploads (matches `SyncWorker` limit).
- On each run: fetches `pending` and `failed` jobs where `next_retry_at` is null or in the past, sorted oldest-first.
- Per job: calls `DriveApi.uploadFile()`. Stores `resumable_uri` in the job row before streaming begins. On interruption, resumes from the stored URI on next run.
- On success: `status = completed`, `drive_file_id` recorded.
- On transient failure: `retry_count++`, `next_retry_at` set, `status = failed`.
- After 3 failures: `status = dead`, `failure_reason` recorded.
- On auth expiry (401): pauses queue (all `uploading` → `pending`), fires `DriveAuthExpired` event.

**Retry schedule:** 30 s → 2 min → 10 min (matches `RetrySchedule` in existing sync engine).

**Trigger sources:**
1. **Wi-Fi connect** — `connectivity_plus` listener detects `ConnectivityResult.wifi`; starts worker if `drive_auto_upload_enabled = true`.
2. **Manual** — "Upload All" button resets all `failed` jobs (not `dead`) to `pending` and starts worker. Per-item tap on any `FAILED` row (including `dead`) resets that job's `retry_count = 0` and `status = pending`.
3. **WorkManager periodic tick** — runs every ~15 min in background; only proceeds if on Wi-Fi.

### `DriveApi` additions

```dart
Future<String> createFolder(String name, String parentId);

Future<String> uploadFile({
  required String localPath,
  required String driveParentId,
  required String fileName,
  String? resumableUri,
  void Function(int sent, int total)? onProgress,
});
```

`uploadFile` returns the Drive file ID on success. Files >5 MB use the Drive v3 resumable upload protocol. `resumableUri` is passed when resuming an interrupted upload.

---

## 4. UI

### Home screen banner

- Visible only when `DriveUploadJobs` has at least one non-completed job.
- Shows: file count, total size, connectivity status (Wi-Fi / No Wi-Fi).
- Tapping opens `UploadQueueScreen`.
- Shows "No Wi-Fi" warning variant when offline.

### Upload Queue screen

**Summary bar (top):**
- Total file count and size of non-completed jobs.
- Auto-upload toggle (backed by `flutter_secure_storage`).

**Progress bar (shown during active upload):**
- "Uploading… 12 of 23" with percentage and filled bar.

**File list:**
- Each row: file icon (photo 🖼 / shapefile 📦), file name, assignment ID, size, capture date.
- Status chip: `PENDING`, `UPLOADING`, `✓ DONE`, `FAILED`.
- Both `failed` (auto-retry eligible) and `dead` (exhausted retries) jobs display as `FAILED`.
- Failed rows show failure reason inline and are tappable to manually retry (resets `retry_count = 0`, `status = pending`).
- "Upload All" resets only `failed` jobs (not `dead`). Dead jobs require an explicit per-item tap to retry.

**"Upload All" button:**
- Disabled when already uploading or no Wi-Fi is available.

---

## 5. Authentication

**Scope:** Add `https://www.googleapis.com/auth/drive.file` to the `GoogleSignIn` scopes list. `drive.file` grants access only to files created by this app.

**First-time consent:** If the enumerator hasn't granted Drive access before, `requestScopes()` triggers the OS consent dialog on the first upload attempt. This happens once; the session is persisted by `flutter_secure_storage`.

**Re-auth flow:** On 401 from the Drive API:
1. Worker pauses — all `uploading` jobs revert to `pending`.
2. `DriveAuthExpired` event fires via a `StreamController`.
3. UI shows snackbar: "Sign in again to resume uploads" with "Sign In" action.
4. After successful re-auth, worker resumes automatically.

---

## 6. Error Handling

| Failure type | Worker action | UI surface |
|---|---|---|
| Network drop mid-upload | Store `resumable_uri`, `status = failed`, schedule retry | `FAILED · Network dropped` |
| Auth expired (401) | Pause queue, fire `DriveAuthExpired` | Snackbar + "Sign In" action |
| File not found on disk | `status = dead`, `failure_reason = "File missing"` | `FAILED · File missing` |
| Drive quota exceeded (403) | All pending jobs → `dead` | Banner: "Drive storage full" |
| File >5 GB (Drive limit) | `status = dead` at enqueue time | `FAILED · File too large` |
| Transient server error (5xx) | Retry up to 3×, then `dead` | `FAILED · Server error` |

Local files are never deleted. The job row is what gets marked complete; the original file stays on device regardless of upload outcome.

---

## 7. Out of Scope

- Real-time syncing during data collection
- Editing or deleting files already uploaded to Drive
- Supervisor review workflow
- Cellular data uploads
- Backfilling queue for assignments completed before this feature ships (separate migration story)

---

## 8. Definition of Done

- All acceptance criteria pass on Android and iOS.
- Tested with ≥50 mixed files (photos + shapefiles).
- Tested under simulated Wi-Fi drop and reconnect.
- Resumable upload verified: partial upload resumes rather than restarts after interruption.
- Drive folder structure verified by supervisor account.
- Auto-upload toggle persists across app restarts.
- Re-auth flow tested with expired token.
- Logging in place for all failure types.
