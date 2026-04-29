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
shapefiles are uploaded back. Acceptable storage media: GitHub repo, Google
Drive, or FileZilla/FTP.

This document scopes a small set of user stories that bring the FireCheck mobile
app into compliance by replacing the **delivery boundary** (currently Supabase
upload) with a strict shapefile in / shapefile out workflow. Internal app
architecture (Drift + Supabase) remains for the team's own use.

---

## Decisions

| Topic | Choice | Rationale |
|---|---|---|
| Scope | Replace the delivery boundary, not the whole sync engine. | Follows the supervisor's instruction without scrapping working internal infra. |
| Deliverable contents | **Only shapefile component files** (`.shp/.dbf/.shx/.prj`). No photos, no manifest, no readme in the zip. | Strict reading of the supervisor's instruction: "download the shape files… upload the attributed shape files." |
| Photos | Stay inside the app (Drift + Supabase Storage) for the team's own records; never part of the deliverable. | Photos can't go inside a shapefile, and the supervisor didn't ask for them. |
| Storage backend | **Google Drive**. | UP accounts already exist, supervisor familiarity, stable API; FileZilla needs hosted FTP we don't have, GitHub is awkward for >100 MB updates. |
| Multi-tab buildings | One row per structure with repeated geometry; `struct_idx` column distinguishes them. | Cleaner for GIS analysis than numbered columns; expected by QGIS. |
| CRS — internal & Mapbox | EPSG:4326 (WGS84 lat/lon). | What GPS and Mapbox use natively; no transformation cost in the live map view. |
| CRS — shapefile deliverable | **EPSG:32651 (WGS 84 / UTM zone 51N)**. | Projected to meters, so building footprints and road lengths measure correctly out of the box. Same WGS84 datum as GPS — no datum-shift error. Covers Cebu, Manila, Palawan, most of the Philippines (120°–126° E). PRS92 zones (3123–3125) considered but rejected: ~150 m datum offset from WGS84 introduces transformation uncertainty for a GPS-driven survey app. Assignments east of 126° E should switch to EPSG:32652 (UTM zone 52N) — implementation should make this configurable per assignment. |
| Zip | Used only as transport for the multi-file shapefile set. Nothing else inside. | Convenience — Drive doesn't preserve directory grouping for loose `.shp/.dbf/.shx/.prj` uploads. |

---

## Personas

- **Enumerator (E)** — field worker using the FireCheck app.
- **Course Supervisor (S)** — uploads input shapefiles to shared storage; downloads and reviews output shapefiles.

---

## User Stories

### Epic 1 — Input distribution

#### FF-1 — Pre-stage assignment input shapefiles

> **As a** Supervisor, **I want to** upload input shapefiles (boundary, buildings, roads) to a shared Google Drive folder, **so that** enumerators can download their assignment.

**Acceptance criteria**

- Drive path: `/firecheck/inbox/<assignment_id>/input.zip`.
- Zip contains exactly:
  - `boundary.{shp,dbf,shx,prj}` — assignment polygon.
  - `buildings.{shp,dbf,shx,prj}` — initial building polygons (attributes may be sparse).
  - `roads.{shp,dbf,shx,prj}` — initial road polylines.
- Nothing else — no `manifest.json`, no `readme.txt`, no images.
- CRS = EPSG:32651 (WGS 84 / UTM zone 51N), verified via the `.prj` file. (Eastern-Mindanao assignments: EPSG:32652 instead.)
- Opens cleanly in QGIS with no warnings.

#### FF-2 — Download assignment input on "Get Maps"

> **As an** Enumerator, **I want** "Get Maps" to fetch my input shapefiles from Drive, **so that** I can work fully offline afterward.

**Acceptance criteria**

- Authenticates to Drive, lists assignments visible to the signed-in account.
- Downloads `input.zip`, extracts, imports features into Drift, preserving original `feature_id` from the `.dbf`.
- Existing Mapbox tile-pack download flow continues alongside this step.
- Idempotent: re-tapping "Get Maps" while online refreshes only if Drive's `modifiedTime` on `input.zip` is newer than the locally stored value.

#### FF-3 — Reject malformed input shapefiles

> **As an** Enumerator, **I want** the app to reject a broken input shapefile at download time, **so that** I don't waste a day on an unusable assignment.

**Acceptance criteria**

- Pre-import validation checks:
  - All required `.shp/.dbf/.shx/.prj` files present for each layer.
  - CRS matches the configured assignment CRS (default EPSG:32651). Mismatched CRS is rejected — supervisor must reproject before re-uploading.
  - Required attribute columns present in `buildings.dbf` and `roads.dbf`.
- On import, geometries are reprojected from the file CRS to EPSG:4326 (WGS84) for in-app storage and Mapbox display.
- On any failure: clear error citing what's missing; no partial import.

### Epic 2 — Attribution (existing app behavior, confirmed)

#### FF-4 — Attribute features offline

> **As an** Enumerator, **I want to** fill building, road, and OLP forms while offline, **so that** I can survey without connectivity.

**Acceptance criteria**

- Existing forms (Identity, Construction, Cost, Fire-fighting, Fire load, OLP) keep working unchanged.
- Photos persist locally for the team's own use; they are **not** included in the shapefile deliverable.
- Multi-tab structures continue to work; each tab becomes a separate output row in FF-5.

### Epic 3 — Output packaging

#### FF-5 — Export attributed shapefiles

> **As an** Enumerator, **I want** the app to package my completed work as attributed shapefiles, **so that** I can hand it back in the format the course expects.

**Acceptance criteria**

- Output zip name: `output_<assignment_id>_<enumerator_id>_<yyyymmdd-hhmm>.zip`.
- Zip contains exactly:
  - `buildings.{shp,dbf,shx,prj}` — one row per structure (multi-tab → repeated geometry, distinct `struct_idx`).
  - `roads.{shp,dbf,shx,prj}` — attributed road polylines.
- Nothing else — no photos, no manifest, no readme.
- `.dbf` column names ≤ 10 characters (shapefile spec).
- All required survey fields populated per row; null values explicitly marked, not blank.
- CRS = EPSG:32651 (WGS 84 / UTM zone 51N), declared in the `.prj` file. Geometries are reprojected from the in-app EPSG:4326 store to EPSG:32651 at export time. (Eastern-Mindanao assignments emit EPSG:32652 instead.)

#### FF-6 — Pre-upload integrity check

> **As an** Enumerator, **I want** the app to verify the shapefiles are complete before letting me upload, **so that** I don't deliver a broken submission.

**Acceptance criteria**

- Runs automatically on the Review screen.
- **Blockers** (must be zero before upload is enabled):
  - Any feature missing a required attribute.
  - Any feature with invalid geometry (non-closed polygon, self-intersection, etc.).
- **Warnings** (non-blocking):
  - Unusual values (e.g. `n_storeys > 50`).
- Upload button is disabled until blockers = 0.

### Epic 4 — Upload

#### FF-7 — Upload attributed shapefiles to shared storage

> **As an** Enumerator, **I want to** upload my completed shapefiles to Drive when I have Wi-Fi, **so that** the supervisor can review them.

**Acceptance criteria**

- Triggered from existing Review-screen "Upload Data" button.
- Biometric gate (existing behavior) intact.
- Drive path: `/firecheck/outbox/<assignment_id>/<enumerator_id>/output_<…>.zip`.
- **Idempotent:** re-uploading the same logical output saves a `_v2`, `_v3`, … sibling — never overwrites the previous version.
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

> **As a** Supervisor, **I want to** open any uploaded shapefile in QGIS without conversion, **so that** I can spot-check work using standard GIS tooling.

**Acceptance criteria**

- Shapefile loads in QGIS with no warnings.
- Attributes are inspectable via QGIS's standard Attribute Table.
- Geometry is valid (no self-intersections, all polygons closed).

---

## Out of scope

- Photos in the deliverable — they stay inside the app.
- A manifest or readme file in the deliverable.
- Real-time multi-enumerator collaboration on the same assignment.
- Server-side validation or automated bounce-back of bad uploads — supervisor reviews manually.
- Re-versioning input shapefiles after enumerators have started (input frozen at download time).
- Migrating the rest of the app off Supabase — internal storage stays Drift + Supabase; only the **delivery boundary** changes.
- Switching to GeoPackage or KMZ — supervisor explicitly mentioned shapefiles.

---

## Open questions to confirm with supervisor

1. **Storage backend** — confirm Google Drive (vs. FileZilla / GitHub repo).
2. **Multi-tab buildings** — confirm "one row per structure with repeated geometry" is the expected GIS shape (vs. numbered columns on a single row).
3. **Required attribute columns** — confirm the supervisor's expected column list. The app currently captures dozens of fields; the supervisor may only want a subset.
4. **Re-upload semantics** — confirm `_v2/_v3` suffixed sibling files (this design's choice) vs. timestamp-only filenames vs. overwriting.
5. **Boundary in output** — confirm whether the supervisor wants `boundary.shp` echoed back in the output zip, or only `buildings` and `roads`.
6. **CRS** — confirm EPSG:32651 (WGS 84 / UTM zone 51N) for the deliverable. Alternative for stricter government-style work: EPSG:3124 (PRS92 / Philippines zone 4) — the official Philippine national datum for the Cebu/Visayas area, but introduces a ~150 m datum-shift transformation from GPS source.

---

## Mapping to existing FireCheck modules

| Story | Touches |
|---|---|
| FF-2, FF-3 | `lib/features/assignment/` (Get Maps flow), new `lib/core/sync/shapefile/` for shapefile import |
| FF-5, FF-6 | `lib/core/sync/` (replaces bundle export), new `lib/core/sync/shapefile/` for shapefile export |
| FF-7, FF-8 | `lib/core/sync/worker/`, replace Supabase Storage adapter with Google Drive adapter |
| FF-9 | `lib/core/auth/`, add Google OAuth alongside existing Supabase auth |
| FF-10 | `docs/file-conventions.md` (new) |

The existing **outbox / retry / WorkManager** machinery from Phase 4a is kept — only the upload *destination* and *payload format* change.
