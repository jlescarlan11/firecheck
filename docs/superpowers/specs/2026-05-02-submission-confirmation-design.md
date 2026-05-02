# Submission Confirmation with Remote Path Visibility — Design Spec

**US-30** | 2026-05-02

## 1. Background

After an enumerator uploads their completed photos and shapefiles to Google Drive (US-29), they receive no feedback about where the data was stored. This creates uncertainty, duplicate uploads, and support tickets. This feature adds a persistent inline confirmation card to the Review screen that shows the Drive folder path, a reference ID, and the confirmed timestamp — so the enumerator knows exactly where their work landed.

## 2. Scope

- **In scope:** Drive upload confirmation card (success + failure states), Drive folder URL + timestamp persistence on the `assignments` table, copy-to-clipboard, open-in-Drive link, retry flow.
- **Out of scope:** Supabase submission confirmation (existing flow unchanged), enumerator user guide documentation, QA sign-off process.

## 3. Architecture

Four pieces, each with one responsibility:

| Piece | Type | Change |
|---|---|---|
| `GoogleDriveApi` | existing | add `uploadAssignmentFiles()` → returns `(folderPath, folderUrl)` |
| `DriveUploadNotifier` | new | owns Drive upload lifecycle; writes result to DB on success |
| `assignments` Drift table | existing | add `driveFolderUrl` + `driveUploadConfirmedAt` nullable columns |
| Review screen | existing | observes `DriveUploadNotifier`; renders confirmation or error card |

**Flow:**

1. Enumerator taps "Upload to Drive" on the Review screen.
2. `DriveUploadNotifier.startUpload(assignmentId)` transitions `Idle → InProgress` and calls `GoogleDriveApi.uploadAssignmentFiles()` with a progress callback.
3. On success: notifier calls `AssignmentsRepository.setDriveUploadResult(assignmentId, folderUrl, confirmedAt)`, then transitions to `Success`.
4. Review screen observes the notifier state and renders the inline confirmation card.
5. On app restart: notifier checks `AssignmentsRepository.getDriveUploadResult(assignmentId)`. If non-null, it initialises directly to `Success` — the card appears without re-uploading.

## 4. Data Model

Three new nullable columns added to `lib/core/db/tables/assignments.dart`:

```dart
TextColumn get driveFolderPath => text().nullable()(); // "FieldData/john123/2026-05-02/"
TextColumn get driveFolderUrl => text().nullable()();  // full Drive URL
DateTimeColumn get driveUploadConfirmedAt => dateTime().nullable()();
```

- `driveFolderPath` — human-readable relative path (e.g. `FieldData/john123/2026-05-02/`), taken directly from the Drive API's `File.name` at upload time. Stored so it can be displayed on cold restart without URL parsing or re-querying Drive.
- `driveFolderUrl` — full Drive folder URL (`https://drive.google.com/drive/folders/…`). Used for copy-to-clipboard and "Open in Drive".
- `driveUploadConfirmedAt` — timestamp returned by the Drive API on upload success.
- **Reference ID** — no new column. The existing `assignments.id` (UUID) is truncated to its first 8 characters, uppercased, and prefixed: `ASN-{id.substring(0,8).toUpperCase()}`. Formatted in the notifier and passed as `DriveUploadSuccess.referenceId`.

Requires a Drift schema migration.

## 5. DriveUploadNotifier

**File:** `lib/features/review/application/drive_upload_notifier.dart`

### State

```dart
sealed class DriveUploadState {
  const DriveUploadState();
}

class DriveUploadIdle extends DriveUploadState {
  const DriveUploadIdle();
}

class DriveUploadInProgress extends DriveUploadState {
  final double progress; // 0.0–1.0
  const DriveUploadInProgress(this.progress);
}

class DriveUploadSuccess extends DriveUploadState {
  final String folderPath;    // "FieldData/john123/2026-05-02/"
  final String folderUrl;     // full Drive URL
  final String referenceId;   // "ASN-4a8f91c"
  final DateTime confirmedAt;
  const DriveUploadSuccess({
    required this.folderPath,
    required this.folderUrl,
    required this.referenceId,
    required this.confirmedAt,
  });
}

class DriveUploadFailure extends DriveUploadState {
  final String message;
  final bool canRetry;
  const DriveUploadFailure({required this.message, required this.canRetry});
}
```

### Behaviour

- `startUpload(assignmentId)` — `Idle → InProgress → Success | Failure`
- `retry(assignmentId)` — resets to `Idle`, then calls `startUpload()`
- **Init from DB** — on first build, reads `assignments.driveFolderPath`, `driveFolderUrl`, and `driveUploadConfirmedAt`. If all three are non-null, reconstructs `DriveUploadSuccess` directly from the stored values plus the formatted `referenceId`. No Drive API call needed.
- Notifier never emits `Success` unless all files are confirmed uploaded and the DB write has completed.

## 6. UI — Confirmation Card

The card appears inline on the Review screen, below the existing upload progress bar. It replaces no existing UI — it is additive.

### Success card

- Green border (`#16a34a`), light green background (`#f0fdf4`)
- Header: ✅ "Submitted to Google Drive"
- **Remote Path** row: human-readable folder path in monospace + "📋 Copy" button (copies full Drive URL to clipboard)
- **Reference ID** + **Confirmed** in a two-column row below
- "Open in Google Drive →" tappable link at the bottom (opens `folderUrl` in the system browser/Drive app)

### Failure card

- Red border (`#dc2626`), light red background (`#fef2f2`)
- Header: ❌ "Upload Failed"
- Descriptive error message (network error, auth error, or partial failure with file count)
- "Retry Upload" button (full width) — calls `notifier.retry()`
- Auth failure: button label changes to "Re-authenticate" and `canRetry` is `false` until re-auth completes

### Accessibility

- Success card announces: "Upload successful. Remote path: FieldData/john123/2026-05-02/. Reference ID: ASN-4a8f91c."
- Failure card announces: "Upload failed. [error message]. Retry button available."
- Copy button has a semantic label: "Copy remote path to clipboard"

## 7. Error Handling

| Scenario | `canRetry` | User sees |
|---|---|---|
| Network drops mid-upload | `true` | Error card + "Retry Upload" |
| Drive auth expired | `false` | Error card + "Re-authenticate" |
| Partial upload (some files fail) | `true` | Error card naming failed file count; retry re-attempts only failed files |

No partial `Success` state. The notifier transitions to `Success` only when all files are confirmed and the DB write is complete.

Supabase submission failures remain handled by the existing Failed Jobs section — entirely separate from Drive upload failures.

## 8. Testing

### Unit — `DriveUploadNotifier`

- Happy path: `Idle → InProgress → Success`, verifies `AssignmentsRepository.setDriveUploadResult` called
- Network failure: `Idle → InProgress → Failure(canRetry: true)`
- Auth failure: `Idle → InProgress → Failure(canRetry: false)`
- Cold-start init: notifier initialises to `Success` when `assignments.driveFolderUrl` is already set
- Retry: `Failure → Idle → InProgress → Success`

### Unit — `AssignmentsRepository`

- `setDriveUploadResult` writes all three columns: `driveFolderPath`, `driveFolderUrl`, `driveUploadConfirmedAt`
- `getDriveUploadResult` returns `null` when unset; returns correct values when set

### Widget — Review screen confirmation card

- Success state: path, reference ID, timestamp, copy button, and "Open in Drive" link all render
- Failure state: error message and retry button render; no path shown
- Copy button calls `Clipboard.setData` with the full Drive URL
- Card absent when state is `Idle` or `InProgress`
- Persistence: card renders from DB value on cold start (notifier initialised to `Success`)

## 9. Open Questions (resolved)

| Question | Decision |
|---|---|
| Clickable link? | Yes — taps open `folderUrl` in system browser/Drive app |
| Audit logging? | Yes — existing sync_jobs mechanism; no new table |
| Path format? | Relative path displayed; full Drive URL copied to clipboard |
| Persistence? | Persistent — stored in `assignments.driveFolderUrl` |
| Reference ID? | `assignments.id` formatted as `ASN-{shortId}` |
