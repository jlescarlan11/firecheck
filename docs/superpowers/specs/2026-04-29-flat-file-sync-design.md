# Flat-File Sync — User Stories & Design

**Date:** 2026-04-29
**Status:** Draft, awaiting review
**Author:** John Lester Escarlan (with brainstorming assistance)

---

## Background

The original FireCheck spec referenced a "server" for retrieving maps. The course
supervisor (Dulaca, R.C.) clarified on 2026-04-29 that no such API server exists
or is intended. The supervisor's actual model is **flat file storage**: a shared
repository where input shapefiles are placed for download, and attributed
shapefiles are uploaded back. Acceptable storage media include a GitHub repo,
Google Drive, or FileZilla/FTP.

This document scopes a small set of user stories to bring the FireCheck mobile
app into compliance with that instruction by replacing the **delivery boundary**
(currently Supabase REST + Storage) with a flat-file workflow built on
shapefile bundles. Internal app architecture (Drift + Supabase) remains.

---

## Decisions

| Topic | Choice | Rationale |
|---|---|---|
| Scope | Replace the delivery boundary, not the whole sync engine. | Follows the supervisor's instruction without scrapping working internal infra. |
| Photos | Filename in .dbf column, photos in sibling `photos/` folder, zipped together. | Standard GIS convention; opens in QGIS; keeps the deliverable a real shapefile. |
| Storage backend | **Google Drive**. | UP accounts already exist, supervisor familiarity, stable API; FileZilla needs hosted FTP we don't have, GitHub is awkward for >100 MB photo bundles. |
| Multi-tab buildings | One row per structure with repeated geometry; `struct_idx` column distinguishes them. | Cleaner for GIS analysis than numbered columns. |
| CRS | EPSG:4326 (WGS84) end-to-end. | Mapbox already operates here; no projection conversion needed. |

---

## Personas

- **Enumerator (E)** — field worker using the FireCheck app.
- **Course Supervisor (S)** — uploads input bundles to shared storage; downloads and reviews output.

---

## User Stories

### Epic 1 — Input distribution

#### FF-1 — Pre-stage assignment input as a shapefile bundle

> **As a** Supervisor, **I want to** upload an input bundle (boundary + buildings + roads shapefiles) to a shared Google Drive folder, **so that** enumerators can download their assignment.

**Acceptance criteria**

- Bundle is `input.zip` containing:
  - `boundary.{shp,dbf,shx,prj}` — the assignment polygon
  - `buildings.{shp,dbf,shx,prj}` — initial building polygons (may be empty attributes)
  - `roads.{shp,dbf,shx,prj}` — initial road polylines
  - `manifest.json` — `{ assignment_id, area_name, supervisor, generated_at }`
- Drive path: `/firecheck/inbox/<assignment_id>/input.zip`.
- CRS = EPSG:4326 (verified via `.prj`).
- Bundle opens cleanly in QGIS with no warnings.

#### FF-2 — Download assignment input on "Get Maps"

> **As an** Enumerator, **I want** "Get Maps" to fetch my input bundle from Drive, **so that** I can work fully offline afterward.

**Acceptance criteria**

- Authenticates to Drive, lists assignments visible to the signed-in account.
- Downloads `input.zip`, extracts, imports features into Drift, preserving original `feature_id` from `.dbf`.
- Existing Mapbox tile-pack download flow continues to run alongside this step.
- Idempotent: re-tapping "Get Maps" while online refreshes only if remote `manifest.json:generated_at` is newer than the locally stored value.

#### FF-3 — Reject malformed input bundles

> **As an** Enumerator, **I want** the app to reject a broken input bundle at download time, **so that** I don't waste a day on an unusable assignment.

**Acceptance criteria**

- Pre-import validation checks:
  - All required `.shp/.dbf/.shx/.prj` files present.
  - CRS = EPSG:4326.
  - `manifest.json` parseable and complete.
  - Required attribute columns present in `buildings.dbf` and `roads.dbf`.
- On any failure: clear error citing what's missing; no partial import.

### Epic 2 — Attribution (existing app behavior, confirmed)

#### FF-4 — Attribute features offline

> **As an** Enumerator, **I want to** fill building, road, and OLP forms while offline, **so that** I can survey without connectivity.

**Acceptance criteria**

- Existing forms (Identity, Construction, Cost, Fire-fighting, Fire load, OLP) keep working unchanged.
- Photos persist locally and are tagged with `feature_id` + `structure_idx`.
- Multi-tab structures continue to work; each tab becomes a separate output row in FF-5.

### Epic 3 — Output packaging

#### FF-5 — Export attributed features as a shapefile bundle

> **As an** Enumerator, **I want** the app to package my completed work as a shapefile bundle, **so that** I can hand it back in the format the course expects.

**Acceptance criteria**

- Output zip layout:
  ```
  output_<assignment_id>_<enumerator_id>_<yyyymmdd-hhmm>.zip
    ├── buildings.{shp,dbf,shx,prj}   one row per structure (multi-tab → repeated geometry, distinct struct_idx)
    ├── roads.{shp,dbf,shx,prj}       attributed road polylines
    ├── photos/<feature_id>_<n>.jpg   photos referenced from .dbf
    ├── manifest.json                  assignment_id, enumerator_id, completed_at, feature counts
    └── readme.txt                     column dictionary mapping 10-char .dbf names → human-readable
  ```
- `.dbf` column names capped at 10 characters (shapefile spec).
- `readme.txt` provides the short-name → long-name mapping.
- Photo columns `photo_1`…`photo_n` hold filenames that resolve inside `photos/`.
- All required survey fields present per row; null values explicitly marked, not blank.

#### FF-6 — Pre-upload integrity check

> **As an** Enumerator, **I want** the app to verify the bundle is complete before letting me upload, **so that** I don't deliver a broken submission.

**Acceptance criteria**

- Runs automatically on the Review screen.
- **Blockers** (must be zero before upload is enabled):
  - Any feature missing a required attribute.
  - Any photo column referencing a file not in `photos/`.
- **Warnings** (non-blocking):
  - Unusual values (e.g. `n_storeys > 50`).
- Upload button is disabled until blockers = 0.

### Epic 4 — Upload

#### FF-7 — Upload attributed bundle to shared storage

> **As an** Enumerator, **I want to** upload my completed bundle to Drive when I have Wi-Fi, **so that** the supervisor can review it.

**Acceptance criteria**

- Triggered from existing Review-screen "Upload Data" button.
- Biometric gate (existing behavior) intact.
- Drive path: `/firecheck/outbox/<assignment_id>/<enumerator_id>/output_<…>.zip`.
- **Idempotent:** re-uploading the same logical bundle saves a `_v2`, `_v3`, … sibling — it never overwrites the previous version.
- Resumable across Wi-Fi drops (chunked upload or full retry — implementer's choice).
- On success: assignment locks (existing behavior).

#### FF-8 — Confirm upload landed

> **As an** Enumerator, **I want** a clear confirmation including the remote path, **so that** I know the work is delivered.

**Acceptance criteria**

- After successful upload, the app shows the Drive file path / shareable link with a "Copy" action.
- On failure, the error message and a "Retry" affordance are shown.

### Epic 5 — Cross-cutting

#### FF-9 — Authenticate to shared storage

> **As an** Enumerator, **I want to** sign in once with my UP Google account, **so that** all subsequent downloads and uploads are attributed to me.

**Acceptance criteria**

- Google sign-in on first launch.
- Refresh tokens persisted in `FlutterSecureStorage`.
- Auto-refresh; on refresh failure, prompt re-auth.
- Sign-out option from settings.

#### FF-10 — Predictable folder & filename convention

> **As a** Supervisor, **I want** every input and output to follow a documented naming convention, **so that** I can locate any enumerator's work without guessing.

**Acceptance criteria**

- `docs/file-conventions.md` documents the inbox / outbox layouts (per FF-1, FF-7).
- App refuses to upload if `assignment_id` or `enumerator_id` is missing or invalid.
- Different enumerators never collide — each lives in their own subfolder under the assignment.

#### FF-11 — Open enumerator output directly in QGIS

> **As a** Supervisor, **I want to** open any uploaded bundle in QGIS without conversion, **so that** I can spot-check work using standard GIS tooling.

**Acceptance criteria**

- Bundle loads in QGIS with no warnings.
- A QGIS attribute-form action wired to the `photo_1` column previews the photo from `photos/`.
- `manifest.json` counts let the supervisor sanity-check against the survey area.

---

## Out of scope

- Real-time multi-enumerator collaboration on the same assignment.
- Server-side validation or automated bounce-back of bad uploads — supervisor reviews manually.
- Re-versioning input bundles after enumerators have started (input is frozen at download time).
- Migrating the rest of the app off Supabase — internal storage stays Drift + Supabase; only the **delivery boundary** changes.
- Switching to GeoPackage or KMZ — supervisor explicitly mentioned shapefiles.

---

## Open questions to confirm with supervisor

These are flagged for explicit confirmation before implementation begins:

1. **Photo handling convention** — confirm sibling `photos/` folder + filename in `.dbf` column is acceptable (vs. embedded GeoPackage).
2. **Storage backend** — confirm Google Drive (vs. FileZilla / GitHub repo).
3. **Multi-tab buildings** — confirm "one row per structure with repeated geometry" is the expected GIS shape (vs. numbered columns on a single row).
4. **Required attribute fields** — confirm the supervisor's expected column list, not the app's internal field list. The `readme.txt` dictionary should match what the supervisor wants to see.
5. **Re-upload semantics** — confirm `_v2/_v3` suffixed sibling files (this design's choice) vs. timestamp-only filenames vs. overwriting the previous version.

---

## Mapping to existing FireCheck modules

| Story | Touches |
|---|---|
| FF-2, FF-3 | `lib/features/assignment/` (Get Maps flow), new `lib/core/sync/shapefile/` for shapefile import |
| FF-5, FF-6 | `lib/core/sync/` (replaces bundle export), new `lib/core/sync/shapefile/` for shapefile export |
| FF-7, FF-8 | `lib/core/sync/worker/`, replace Supabase Storage adapter with Google Drive adapter |
| FF-9 | `lib/core/auth/`, add Google OAuth alongside existing Supabase auth |
| FF-10 | `docs/file-conventions.md` (new) |

The existing **outbox / retry / WorkManager** machinery from Phase 4a should be kept — only the upload *destination* and *payload format* change.
