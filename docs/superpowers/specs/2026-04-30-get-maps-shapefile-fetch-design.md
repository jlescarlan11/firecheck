# Get Maps — Shapefile Fetch from Drive

**Date:** 2026-04-30
**Status:** Draft, awaiting review
**Author:** John Lester Escarlan (with brainstorming assistance)
**Branch:** 17-as-an-enumerator-i-want-get-maps-to-fetch-my-input-shapefiles-from-drive-so-that-i-can-work-fully-offline-afterward

---

## User Story

> As an Enumerator, I want "Get Maps" to fetch my input shapefiles from Drive, so that I can work fully offline afterward.

---

## Background

The flat-file sync design spec (`2026-04-29-flat-file-sync-design.md`) established that input
shapefiles for each assignment are placed in Google Drive at
`/firecheck/inbox/<assignment_id>/input.zip` by the course supervisor. This story wires up the
"Get Maps" action to fetch that zip, validate and import it into Drift, and then proceed with the
existing Mapbox tile-pack download — leaving the enumerator fully equipped to work offline.

Currently `GetMapsNotifier.start()` calls `AssignmentRepository.fetchAndUpsertCurrent()`, which
pulls assignment data from Supabase. This story replaces that Supabase step with a Drive-based
flow. The rest of the app (Supabase sync, map display, attribution forms) is unchanged.

Google OAuth is in scope. Google Sign-In has not previously existed in the app.

---

## Decisions

| Topic | Choice | Rationale |
|---|---|---|
| Data source | Drive replaces Supabase for assignment input | Follows the flat-file sync design; Supabase is no longer involved during "Get Maps." |
| Google Sign-In placement | Dedicated `/sign-in` onboarding screen, router-guarded | One-time step on first install. Clean gate — no auth friction on subsequent taps of Get Maps. |
| Assignment picker | Always show picker, even for one assignment | Gives the enumerator a confirmation moment before a potentially large download. Keeps screen structure uniform. |
| Storage pre-check | Hard blocker — "Download Selected" disabled when space is insufficient | Failing mid-download is worse than failing upfront. The check is fast and cheap. |
| Retry granularity | Full zip re-download on failure | Shapefiles are typically small (<10 MB). Resumable chunk tracking is complexity not worth the savings. |
| Delta check | Compare Drive `modifiedTime` on `input.zip` against locally stored value | Skip re-download when nothing changed. Fast check; no user friction for up-to-date assignments. |
| DriveApi abstraction | `abstract class DriveApi` + `FakeDriveApi` + `GoogleDriveApi` | Follows the existing `SyncApi`/`OfflinePackAdapter` interface pattern. No real network in tests. |
| Import atomicity | Single Drift transaction covering assignment upsert + feature bulk-insert | All-or-nothing. Any validation or write failure rolls back; no partial state. |
| CRS boundary | EPSG:32651 in shapefile → EPSG:4326 in Drift/Mapbox | Matches the flat-file sync spec. Reprojection happens inside `ShapefileImporter` at import time. |

---

## Personas

- **Enumerator (E)** — field worker using the FireCheck app on an Android device. May be on a
  personal Gmail account; UP institutional account not required.
- **Course Supervisor (S)** — places `input.zip` in Drive and shares the folder with the enumerator.
  Does not use the FireCheck app. See Preconditions in the flat-file sync design spec.

---

## Architecture

### New components

| Component | Location | Responsibility |
|---|---|---|
| `SignInScreen` | `lib/features/auth/presentation/sign_in_screen.dart` | One-time Google OAuth onboarding screen. |
| `GoogleAuthRepository` (abstract) | `lib/features/auth/data/google_auth_repository.dart` | Sign-in, sign-out, token check. |
| `GoogleSignInAuthRepository` | `lib/features/auth/data/google_sign_in_auth_repository.dart` | Real impl: `google_sign_in` + `FlutterSecureStorage`. |
| `FakeGoogleAuthRepository` | `lib/features/auth/data/fake_google_auth_repository.dart` | Test impl: starts signed-in by default. |
| `DriveApi` (abstract) | `lib/core/drive/drive_api.dart` | List assignments, get zip metadata, stream zip download. |
| `GoogleDriveApi` | `lib/core/drive/google_drive_api.dart` | Real impl: Drive REST v3 via `googleapis` package. |
| `FakeDriveApi` | `lib/core/drive/fake_drive_api.dart` | Test impl: configurable assignment list and download events. |
| `DriveAssignment` | `lib/core/drive/drive_assignment.dart` | Value type: `assignmentId`, `inputZipModifiedTime`, `alreadyDownloaded`. |
| `DriveDownloadEvent` (sealed) | `lib/core/drive/drive_download_event.dart` | `DriveDownloadProgress(downloaded, total)` / `DriveDownloadComplete(bytes)`. |
| `ShapefileImporter` | `lib/core/sync/shapefile/shapefile_importer.dart` | Unzip → validate → reproject → Drift write (single transaction). |
| `ShapefileValidationFailure` | `lib/core/errors/failure.dart` | Typed failure for CRS mismatch, missing layers, missing columns. |
| `StorageChecker` (abstract) | `lib/core/device/storage_checker.dart` | `getAvailableBytes()`. Real impl uses `disk_space` package. Fake returns configurable value. |

### Expanded components

| Component | Change |
|---|---|
| `GetMapsState` | New variants: `DiscoveringAssignments`, `PickingAssignment`, `DownloadingShapefiles`, `ImportingShapefiles`, `InsufficientStorage`. Remove `FetchingFeatures`. |
| `GetMapsNotifier` | `start()` restructured; new `selectAssignment(id)` and `confirmDownload()` methods. Gains `DriveApi`, `GoogleAuthRepository`, `ShapefileImporter`, `StorageChecker` dependencies. |
| `GetMapsScreen` | New `_PickingAssignmentView`, `_DownloadingShapefilesView`, `_ImportingShapefilesView`, `_InsufficientStorageView`. Remove `_FetchingFeaturesView`. |
| `assignments` Drift table | Two new nullable columns: `drive_modified_time TEXT`, `drive_folder_id TEXT`. Schema migration v12. |
| App router | `/sign-in` route added. `/get-maps` route gains a `redirect` guard: if `GoogleAuthRepository.isSignedIn()` is false, redirect to `/sign-in`. |

### Unchanged

`FeatureRepository`, `OfflineTilePackRepository`, `OfflinePackAdapter` and all Mapbox tile download
logic, `AssignmentRepository` (minus the removed `fetchAndUpsertCurrent()` method), all
attribution forms, all Supabase sync machinery.

---

## `GetMapsState` — Full Sealed Class

```dart
sealed class GetMapsState {
  const GetMapsState();
  double get overallProgress;
}

// Waiting to tap "Download Selected" (first visit or after cancel/error).
class Idle extends GetMapsState { ... }                                        // 0%

// Calling Drive files.list.
class DiscoveringAssignments extends GetMapsState { ... }                      // 2%

// User is choosing an assignment from the list.
class PickingAssignment extends GetMapsState {                                 // 2%
  final List<DriveAssignment> assignments;
  final String selectedId;
}

// Space is insufficient — "Download Selected" button is disabled.
class InsufficientStorage extends GetMapsState {                               // 2%
  final int requiredBytes;
  final int availableBytes;
}

// Streaming input.zip from Drive.
class DownloadingShapefiles extends GetMapsState {                             // 2–30%
  final int downloaded;
  final int total;
}

// Extracting, validating, reprojecting, and writing to Drift.
class ImportingShapefiles extends GetMapsState { ... }                         // 35%

// Existing: Mapbox tile-pack download.
class DownloadingTiles extends GetMapsState { ... }                            // 35–100%

// Existing: all data ready.
class Ready extends GetMapsState { ... }                                       // 100%

class Cancelled extends GetMapsState { ... }
class GetMapsError extends GetMapsState { ... }
```

---

## `GetMapsNotifier` — Control Flow

### `start()`

1. `state = DiscoveringAssignments`
2. `assignments = await driveApi.listAssignments()` — each entry includes whether the assignment
   is already locally downloaded (derived from whether Drift has a matching `drive_modified_time`).
3. If `assignments.isEmpty` → `state = GetMapsError(NoAssignmentsFailure)` with the empty-state
   message: *"No assignments shared with you yet — ask your supervisor to share the assignment
   folder with the Google account you signed in with."*
4. `state = PickingAssignment(assignments: assignments, selectedId: assignments.first.id)`

### `selectAssignment(String id)`

Updates `selectedId` within the current `PickingAssignment` state. No-op if called in any other
state.

### `confirmDownload()`

Called when the enumerator taps "Download Selected."

1. **Storage pre-check:**
   `needed = await driveApi.getInputZipSize(selected.assignmentId)`
   `available = await storageChecker.getAvailableBytes()`
   If `available < needed` → `state = InsufficientStorage(...)` and return.

2. **Delta check:**
   If `selected.alreadyDownloaded` is true, the locally stored `drive_modified_time` already
   matches the Drive value (this was evaluated when building the `DriveAssignment` list in
   `start()`). Skip straight to step 5.

3. **Download shapefiles:**
   `state = DownloadingShapefiles(downloaded: 0, total: 0)`
   Stream `driveApi.downloadInputZip(assignmentId)`:
   - `DriveDownloadProgress` → update `DownloadingShapefiles` progress
   - `DriveDownloadComplete` → capture `zipBytes`
   - On error → `state = GetMapsError(...)` and return.

4. **Import shapefiles:**
   `state = ImportingShapefiles`
   `await shapefileImporter.importInputZip(zipBytes, assignmentId, modifiedTime, folderId)`
   On `ShapefileValidationFailure` → `state = GetMapsError(...)` and return.

5. **Tile download (existing logic):**
   Fetch current assignment from Drift (just written by importer).
   Upsert `offline_tile_packs` row, `state = DownloadingTiles(0, 0)`.
   Stream `packAdapter.createPack(...)` → update `DownloadingTiles` progress → `state = Ready`.

### `cancel()`

Unchanged. Calls `packAdapter.cancelAllPacks()`. If called during shapefile download, the stream
is abandoned; no Drift writes have occurred yet (transaction starts only at `ImportingShapefiles`).

### `reset()`

Unchanged.

---

## `ShapefileImporter`

### Input

- `zipBytes` — raw bytes of `input.zip` downloaded from Drive
- `assignmentId` — Drive folder name
- `driveModifiedTime` — RFC 3339 string from Drive (stored in Drift for future delta checks)
- `driveFolderId` — Drive folder ID (stored for constructing upload URLs in later stories)

### Steps (all inside a single Drift transaction)

1. **Unzip** — extract in memory; fail if zip is corrupt.
2. **Validate structure** — `boundary.{shp,dbf,shx,prj}`, `buildings.{shp,dbf,shx,prj}`,
   `roads.{shp,dbf,shx,prj}` must all be present. Throw `ShapefileValidationFailure` if any
   are missing.
3. **Validate CRS** — read each `.prj` file; confirm EPSG:32651 (or the assignment's configured
   CRS). Throw `ShapefileValidationFailure` with the mismatched CRS on failure.
4. **Validate columns** — confirm required attribute columns are present in `buildings.dbf` and
   `roads.dbf`. Throw `ShapefileValidationFailure` listing missing columns.
5. **Reproject geometries** — transform all coordinates from EPSG:32651 → EPSG:4326.
6. **Write to Drift:**
   - Upsert assignment row: `id = assignmentId`, `boundary_polygon_geojson` from `boundary.shp`,
     `drive_modified_time`, `drive_folder_id`.
   - Bulk-insert building features (preserving `feature_id` from `.dbf`).
   - Bulk-insert road features.
7. On any failure in steps 1–6: transaction rolls back. No partial state in Drift.

### Output

`ImportResult(buildingCount, roadCount, boundaryGeojson)`

---

## `DriveApi` Interface

```dart
abstract class DriveApi {
  /// Lists /firecheck/inbox/ subfolders readable by the signed-in user.
  Future<List<DriveAssignment>> listAssignments();

  /// Expected size of input.zip in bytes (from Drive file metadata).
  Future<int> getInputZipSize(String assignmentId);

  /// Streams download bytes for input.zip.
  Stream<DriveDownloadEvent> downloadInputZip(String assignmentId);
}
```

`GoogleDriveApi` uses the `googleapis` package with the access token from
`GoogleAuthRepository`. `FakeDriveApi` is fully configurable: assignment list, size response,
download event sequence, and configurable failure point.

---

## `GoogleAuthRepository` Interface

```dart
abstract class GoogleAuthRepository {
  Future<bool> isSignedIn();
  Future<void> signIn();   // triggers Google OAuth consent screen
  Future<void> signOut();
}
```

`GoogleSignInAuthRepository` uses the `google_sign_in` package. The refresh token is persisted
via `FlutterSecureStorage` under the key `google_refresh_token`. On app restart, the repository
restores the session silently without triggering the consent screen again.

---

## `SignInScreen`

- Single "Sign in with Google" button (standard Material `FilledButton` with Google logo asset).
- On tap: calls `googleAuthRepository.signIn()`.
- On success: `context.go('/get-maps')`.
- On failure: shows an inline error message and a retry button.
- No back navigation — the screen is a gate, not a navigable destination. The app bar back button
  is hidden; hardware back goes to `/` (home), allowing the user to use other offline features.

---

## `GetMapsScreen` — New Views

| State | View | Key elements |
|---|---|---|
| `DiscoveringAssignments` | `_DiscoveringView` | Spinner + "Looking for your assignments…" |
| `PickingAssignment` | `_PickingAssignmentView` | Scrollable list of `DriveAssignment` rows (name + modified date + already-downloaded badge); tapping a row calls `selectAssignment(id)`; "Download Selected" `FilledButton` at bottom calls `confirmDownload()` |
| `InsufficientStorage` | `_InsufficientStorageView` | Warning icon; "Need X MB free, you have Y MB"; disabled "Download Selected" button; "Free up space and come back" hint |
| `DownloadingShapefiles` | `_DownloadingShapefilesView` | "Downloading shapefiles…"; `LinearProgressIndicator`; `downloaded / total MB`; Cancel button |
| `ImportingShapefiles` | `_ImportingShapefilesView` | "Importing…"; indeterminate `LinearProgressIndicator`; no cancel (fast, <1 s) |

`_FetchingFeaturesView` is removed. All other existing views (`_ProgressView` for tiles, `_ReadyView`,
`_ErrorView`) are unchanged.

---

## Drift Schema Migration (v12)

```dart
// In assignments table definition:
TextColumn get driveModifiedTime => text().nullable()();
TextColumn get driveFolderId     => text().nullable()();
```

Both columns are nullable for backward compatibility with existing Supabase-sourced assignment
rows. A Drift migration step adds the columns with `ALTER TABLE assignments ADD COLUMN`.

---

## Error Handling

| Scenario | State | User message |
|---|---|---|
| No assignments in Drive | `GetMapsError` | "No assignments shared with you yet — ask your supervisor to share the assignment folder with the Google account you signed in with." |
| Network drop during discovery | `GetMapsError` | Failure message + Retry button (re-enters `start()`) |
| Insufficient storage | `InsufficientStorage` | "Need X MB free, you have Y MB." Button disabled. |
| Network drop during zip download | `GetMapsError` | Failure message + Retry button |
| Zip validation failure (missing layer, wrong CRS, missing columns) | `GetMapsError` | Specific message citing what's wrong (e.g., "buildings.dbf is missing required column 'bldg_use'") |
| Tile pack failure | `GetMapsError` | Existing error message + Retry button |

Retry always calls `reset()` + `start()`, re-entering `DiscoveringAssignments`. Successfully
imported Drift data is preserved across retries; if the shapefile was already imported, the delta
check will skip re-downloading.

---

## Progress Model

| State | `overallProgress` |
|---|---|
| `Idle` | 0.00 |
| `DiscoveringAssignments` | 0.02 |
| `PickingAssignment` | 0.02 |
| `InsufficientStorage` | 0.02 |
| `DownloadingShapefiles` | `0.02 + 0.28 * (downloaded / total)` |
| `ImportingShapefiles` | 0.35 |
| `DownloadingTiles` | `0.35 + 0.65 * tileProgress` |
| `Ready` | 1.00 |

---

## Testing

### `ShapefileImporter`
- Valid zip → correct `assignments` + `features` rows in Drift
- Missing layer (e.g., no `roads.shp`) → `ShapefileValidationFailure`, no Drift writes
- Wrong CRS in `.prj` → `ShapefileValidationFailure`
- Corrupt zip → `ShapefileValidationFailure`
- Missing required `.dbf` column → `ShapefileValidationFailure` citing column name

### `GetMapsNotifier`
- Empty assignment list → `GetMapsError` with no-assignment message
- Single assignment, not downloaded → full flow: `DiscoveringAssignments → PickingAssignment → DownloadingShapefiles → ImportingShapefiles → DownloadingTiles → Ready`
- Single assignment, already downloaded (modifiedTime matches) → delta skip: `DiscoveringAssignments → PickingAssignment → DownloadingTiles → Ready`
- Download failure mid-stream → `GetMapsError`
- Validation failure → `GetMapsError`
- Insufficient storage → `InsufficientStorage` (button disabled, no download starts)
- Cancel during shapefile download → `Cancelled`, Drift unchanged

### Widget tests
- `_PickingAssignmentView`: "Download Selected" enabled; tapping a row updates selection
- `_InsufficientStorageView`: "Download Selected" is disabled
- `_DiscoveringView`, `_DownloadingShapefilesView`, `_ImportingShapefilesView`: renders without error

---

## Out of Scope

- Uploading attributed shapefiles back to Drive (covered by later stories in the flat-file sync spec)
- Two-way sync or editing shapefiles
- Support for multiple simultaneous active assignments (one assignment is worked on at a time)
- Google account management or switching accounts within the app
