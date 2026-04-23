# FireCheck Mobile — Design Spec

**Date:** 2026-04-24
**Status:** Draft v1 (brainstorming output)
**Companion doc:** PRD supplied at brainstorming time

## 1. Summary

A single Flutter Android app that replaces the two legacy FireCheck apps (Attribution + Household Survey). Enumerators log in, download an assigned map bundle with an offline basemap pack, walk the boundary in the field collecting structure attribution and optional OLP household-survey data with photo evidence, then upload on return. Offline-first is a structural property of the app (every write lands in local SQLite first; a background sync worker drains an outbox to Supabase). School-project scope: no existing backend, Supabase as BaaS.

## 2. Goals & Non-Goals

Carried over from the PRD and not re-litigated here. Notable deviation: the PRD lists "offline tile basemap" as a v2 enhancement. This spec **promotes offline basemap tiles into the MVP** because "offline-first" without a basemap is a degraded field experience — enumerators need to orient themselves against real streets and landmarks.

### Goals (MVP)

1. One app handling structure attribution and household survey on the same feature.
2. Offline-first — a full field day with no connectivity loses no work.
3. Autosaved, resumable forms — partial answers are never lost.
4. Photo evidence — at least one required photo per completed submission.
5. Cleaner uploads — inline validation + pre-submit review screen.
6. **(Promoted from v2)** Offline basemap tiles pre-downloaded per assignment.

### Non-Goals (MVP)

- Web admin dashboard (assumed server-side elsewhere).
- Real-time multi-enumerator collaboration.
- iOS (v2; stack chosen so iOS is a recompile, not a rewrite).
- Map editing beyond "add new feature" (no polygon reshape).
- In-app messaging between enumerator and supervisor.
- Supervisor approval flow inside the mobile app.

## 3. Stack decisions

| Layer | Choice | Rationale |
|---|---|---|
| Mobile framework | **Flutter** (Android-first, iOS-ready in v2) | Near-native performance for maps + camera; one codebase; iOS v2 is recompile + platform tweaks, not rewrite. |
| State management | **Riverpod** | Modern, testable, handles async streams well; less boilerplate than BLoC. |
| Local DB | **Drift** (SQLite) | Relational, type-safe, reactive streams; near-perfect fit for Assignment → Feature → Submission → Photo. Sync outbox is just another table. |
| Remote backend | **Supabase** | Postgres + **PostGIS** (native geometry types), Auth (JWT + refresh), Storage (S3-compatible), Row Level Security. Generous free tier for a student project. |
| Map renderer | **MapLibre GL Native** via `maplibre_gl` Flutter plugin | Open-source, vector tiles, native performance, first-class offline region packs. Tile source: MapTiler or Protomaps. |
| Auth | Supabase Auth, email + password, long-lived refresh token in secure storage, **biometric unlock** on app open and before Upload Data | No re-entering passwords in the field; biometric cheap to add. |
| Background sync | **WorkManager** (Android) via `workmanager` plugin, wakes on connectivity regained, app resume, periodic 15-min tick, manual retry tap | Reliable Android-native scheduling that survives app kill. |
| Photo pipeline | Camera at full res → resize to 1600 px longest edge, JPEG 85%, EXIF GPS preserved (~200–400 KB) → local app dir → Supabase Storage signed URL | Balances quality and upload size for poor connectivity. |
| Locale | English + Tagalog ARB files | PRD's OLP fields are in Tagalog; keep bilingual labels from the start. |
| Device min | Android 8.0 (API 26) / 3 GB RAM / GPS camera / ~2 GB free storage | Matches mid-range devices typical of volunteer enumerators. |

## 4. High-level architecture

Four layers, top-to-bottom:

1. **Presentation** — Flutter widgets split into feature modules (auth, home, map/survey, forms, photos, review/upload). Riverpod manages state and exposes Drift streams to the UI.
2. **Domain** — pure use cases and logic. `ComputeLebelNgKahinaan` (OLP scoring), `CheckDistance` (50m rule), `ValidateCompleteness`, `EnqueueSyncJob`, etc. Zero Flutter or Supabase dependencies, so unit-testable in isolation.
3. **Data** — repositories mediate between a local Drift store (source of truth for the UI) and remote Supabase (source of truth for the system). Local also includes the MapLibre offline pack and photo files on disk. Remote includes Postgres+PostGIS, Supabase Auth, Storage, and RLS policies enforcing one-assignment-per-enumerator.
4. **Infrastructure** — device capabilities: camera + EXIF, GPS, biometric gate, connectivity monitor, WorkManager, MapLibre renderer.

**Load-bearing principle:** every write goes to Drift first; the UI only reads from Drift via reactive streams; a background worker reconciles Drift → Supabase. Offline-first is a structural guarantee, not a discipline.

## 5. Flutter module layout

Single-package Flutter project, feature-modular layout:

```
lib/
├── main.dart
├── app.dart                         # MaterialApp, router, theme, locale
├── core/
│   ├── db/                          # Drift schema, migrations, DAOs
│   ├── supabase/                    # Supabase client, RLS contract
│   ├── sync/                        # Outbox worker, retry policy, WorkManager glue
│   ├── location/                    # GPS stream, distance calc
│   ├── photos/                      # Capture, resize, EXIF, local storage
│   ├── connectivity/                # Online/offline stream
│   ├── security/                    # Secure storage, biometric gate
│   ├── geo/                         # GeoJSON helpers, PostGIS ↔ Dart types
│   ├── i18n/                        # English + Tagalog ARB files
│   └── errors/                      # Typed failure model
├── features/
│   ├── auth/                        # Login, biometric unlock
│   ├── home/                        # Home actions, progress snapshot
│   ├── assignment/                  # "Get Maps" download flow, offline pack
│   ├── map/                         # MapLibre view, color-coded features
│   ├── survey/
│   │   ├── building_form/
│   │   ├── road_form/
│   │   ├── olp_survey/              # Household survey sub-module + scoring
│   │   └── multi_submission/        # "+ add another structure" flow
│   ├── new_feature/                 # Long-press add building/road
│   ├── review/                      # Pre-submit summary + validation
│   └── upload/                      # Sync status UI, retry controls
└── generated/                       # Drift, l10n, etc.
```

**Boundary rules:** features depend on `core`; `core` never depends on `features`. `domain` logic lives inside `core` folders scoped to the concern (`core/sync` hosts sync use cases; `features/survey/olp_survey` hosts OLP scoring since it's tightly coupled to that feature).

## 6. Data model

Client-generated UUIDs are the primary keys everywhere user data flows. They're minted locally at insert-time and sent unchanged on sync — retries and offline creation never collide. No auto-incrementing integers in user-data tables.

### Mirrored tables (local Drift ↔ remote Supabase)

**`enumerators`**
- `id` (uuid, = Supabase Auth user id)
- `username`, `display_name`

**`assignments`**
- `id` (uuid), `enumerator_id` (uuid, RLS: `= auth.uid()`)
- `campaign_id` (uuid)
- `boundary_polygon` — `text` (GeoJSON) locally / `geography(Polygon)` on server
- `downloaded_at`, `submitted_at`
- `status` enum: `assigned | in_progress | submitted`

**`features`**
- `id` (uuid), `assignment_id`
- `feature_type` enum: `building | road`
- `geometry` — GeoJSON locally / PostGIS geography on server (Polygon / LineString / Point)
- `is_new` (bool — flags features added in-field by enumerator for supervisor verification)
- `status` enum, **local-only** (derived from submissions)

**`submissions`**
- `id`, `feature_id`, `submitted_by`
- `created_at`, `updated_at`
- `does_not_exist` (bool), `remarks` (text)
- `sync_status` enum, **local-only**: `draft | queued | uploaded | failed`

**`building_attributes`** (1:1 with submission when `feature_type=building`)
- `cbms_id`, `name`, `ra_9514_type`
- `storeys`, `material`
- `cost_is_exact`, `cost_amount`, `cost_estimate_range`
- `fire_fighting_facilities` (text[]), `fire_load` (text[])

**`road_attributes`** (1:1 with submission when `feature_type=road`)
- `is_bridge`, `road_name`, `width_meters`
- `road_features` (text[]: vendor, pedestrian, parking, others)
- `others_description` (conditional)

**`household_surveys`** (0..1 per submission — optional OLP form)
- `construction_details`, `kaayusan`, `koneksyong_elektrikal`, `kusina`, `daanan_o_labasan` (all jsonb with structured sub-fields)
- `lebel_ng_kahinaan` enum (computed): `Labis na Mapanganib | Mayroong Dapat Ipangamba | Ligtas ang Iyong Tahanan`
- `safety_suggestions` (text, computed)

**`photos`**
- `id`, `submission_id`
- `local_path` (file on device, never sent to server)
- `storage_path` (Supabase Storage path, set after upload)
- `captured_at`, `gps_lat`, `gps_lng` (from EXIF)
- `upload_status` enum, **local-only**: `pending | uploaded | failed`

**`ra_9514_types`** (config table — fetched on "Get Maps", hardcoded fallback in app bundle)
- `code`, `label_en`, `label_tl`

### Local-only tables

**`sync_jobs`** — drives the background upload worker
- `id`, `entity_type` (submission | photo | new_feature | status_update), `entity_id`
- `status` (pending | in_progress | success | failed | dead)
- `blocks_on_submission_id` (nullable uuid; photo jobs set this to their parent submission so the worker sequences submissions before photos)
- `attempts`, `last_error`, `next_retry_at`, `created_at`

**`offline_tile_packs`** — Drift-side metadata tracking for MapLibre's offline region packs. Actual tile bytes live in MapLibre's own SQLite DB (managed by the plugin); this table just stores the pack IDs and progress so our UI can query them without hitting the native layer on every render.
- `id`, `assignment_id`, `maplibre_pack_id`, `region_bounds` (GeoJSON)
- `downloaded_bytes`, `total_bytes`
- `status` (downloading | ready | error)

### Key invariants

- `features.status` is computed from submission presence/completeness — not persisted on the server.
- Mutations that transition data to a sync-ready state (submission Finalize, new-feature Finalize) write the entity change AND insert `sync_jobs` rows in the same Drift transaction. Autosaved drafts and photo captures are local-only until the user finalizes — no sync job exists for them yet, and if the app is uninstalled before Finalize they never reach the server.
- `household_surveys.lebel_ng_kahinaan` and `safety_suggestions` are derived by a pure function in `domain/olp/` — same function runs locally (live form preview) and could run server-side if authoritative scoring is ever needed.
- PostGIS `geography` on server enables supervisor spatial queries (e.g., "all features within 500m of a flagged building"); locally, GeoJSON text is sufficient.
- `ra_9514_types` is cached locally with a hardcoded bootstrap list — the app works offline on first install even if the config fetch fails.

## 7. Offline / sync architecture

### Write path

Two kinds of writes. Only the second touches the outbox.

**Local-only writes (autosave).** Field edits while a form is open, photo capture (insert `photos` row with `upload_status=pending`), and new-feature long-press creation before finalize. These write only to their entity table. Drift commit is enough for local durability; nothing is queued for sync yet.

**Sync-ready writes (Finalize — atomic outbox).** When the user taps "Done" on a submission or "Finalize" on the review screen, the repository opens a Drift transaction that:
- marks the submission `sync_status='queued'`
- inserts a `sync_jobs` row for the submission (`entity_type='submission'`)
- inserts a `sync_jobs` row for each `photos` row attached to that submission (`entity_type='photo'`, `status='pending'`)
- for a feature with `is_new=true`, inserts a `sync_jobs` row for the new feature if it doesn't already exist

All rows commit together. If any insert fails, the whole transaction rolls back and the user can retry. Once committed, sync_jobs rows are durable and the background worker will eventually drain them.

### Submission lifecycle

```
draft → in_progress → ready_to_upload → queued → uploading → uploaded
                                                    ↓ (on failure)
                                                  failed(N) → queued (backoff) → ...
                                                    ↓ (after 5 attempts OR permanent error)
                                                   dead → manual retry from Review screen
```

The `ready_to_upload` transition happens when the user taps "Done" on the form (or "Finalize" on the review screen). Until then, submissions stay in `draft`/`in_progress` and are not in the sync queue — this prevents spamming the server with half-filled forms.

### Photo 2-phase upload

1. PUT file to Supabase Storage via signed URL. Resumable if the library supports it.
2. UPDATE the `photos` row with the returned `storage_path`.

**Ordering:** a submission's row is synced **before** its photos. Photo sync_jobs exist in the queue from Finalize time, but the worker will not process a photo whose parent submission hasn't yet reached `uploaded`. Mechanics: photo jobs carry a `blocks_on_submission_id` field; the worker picks only jobs where that submission is null or `uploaded`. Submissions are small and fast; supervisors see the structured data immediately while photos trickle in.

### Retry & backoff

| Attempt | Delay | Notes |
|---|---|---|
| 1 fail | 30 s | any transient |
| 2 fail | 2 min | any transient |
| 3 fail | 10 min | any transient |
| 4 fail | 1 hr | any transient |
| 5 fail | — | `dead`; manual retry only |

**Special cases:**
- `4xx` (except 401, 409) → `dead` immediately (don't retry a bad payload).
- `401 Unauthorized` → refresh token, retry once. If refresh also fails, prompt full re-login.
- `409 Conflict` (assignment was closed by supervisor while work was pending) → stop the queue, mark assignment `closed_remotely`, show a blocking screen offering export of pending work as JSON+ZIP bundle the user can hand to their supervisor.

### Worker triggers

- Connectivity regained (via `connectivity_plus` stream).
- App foregrounded.
- WorkManager periodic tick (~15 min).
- Manual "Retry" tap from Review or Upload screens.

Max 3 concurrent jobs to avoid saturating a weak cellular connection.

## 8. Key user flows (mapped to features)

### Flow A — First-time setup
Install → login screen (server URL field pre-filled with default) → credentials → biometric enrollment prompt → home.
**Modules:** `features/auth`, `core/security`.

### Flow B — Get Maps
Home → "Get Maps" → biometric gate → download bundle (boundary + features + ra_9514_types) → download MapLibre offline tile pack (bounded region + 200 m buffer, progress UI) → bundle saved in Drift, tiles in MapLibre's offline DB, return to Home.
**Modules:** `features/assignment`, `core/supabase`, `features/map` (for tile pack API).

### Flow C — Survey a structure
Map → tap red polygon → distance check (50 m rule: haversine from current GPS to feature centroid; >50 m shows override/recenter/cancel modal; <30 m GPS accuracy shows weak-GPS banner) → form opens → autosaved on every change → optional "+ Structure 2" tab for densely-packed footprints → optional OLP section expands inline → photo capture with EXIF-preserved resize → "Done" → submission marked `ready_to_upload`, polygon color updates via Drift stream.
**Modules:** `features/map`, `features/survey/*`, `core/location`, `core/photos`.

### Flow D — Add a new structure
Map → "+ New Feature" toggle → long-press location → pick Building or Road → form with point geometry pre-filled → same form flow as Flow C → feature marked `is_new=true`, shown as blue pin.
**Modules:** `features/new_feature`, `features/survey/*`.

### Flow E — Resume after app close
Reopen → biometric unlock → home shows accurate progress (via Drift query) → "Gather Data" reopens map at last-known GPS position → any half-filled form reopens with saved values.
**Modules:** all (relies on Drift-as-source-of-truth).

### Flow F — Pre-submit review & upload
Home → "Upload Data" → biometric gate → review screen lists: total features, completed, incomplete, new features added, photos pending; surfaces validation warnings → "Start Upload" → sync worker drains queue with per-item progress → on success, assignment locked (`submitted_at` set, no further edits).
**Modules:** `features/review`, `features/upload`, `core/sync`.

### Flow G — Connectivity loss mid-survey
Transparent to the user. Writes continue to Drift. Sync worker parks jobs. Offline badge appears in the app header.
**Modules:** `core/connectivity`, `core/sync`.

## 9. Screen-level design notes

**Home** — progress card (e.g., "42 of 100 features · 3 queued · 0 failed"), three action cards in legacy order (Gather Data primary, Get Maps, Upload Data), footer shows offline tile cache size.

**Map (survey mode)** — full-bleed MapLibre view, color-coded polygons (red unfilled / yellow in-progress / green complete / blue new-or-me), GPS pin with accuracy halo, dashed boundary, corner legend, floating toolbar with Follow-Me + New-Feature toggles, offline badge in header when disconnected.

**Building form** — the heaviest screen:
- Tabs at the top represent multi-submission ("Structure 1 / Structure 2 / +") rather than stacking vertically.
- Autosave indicator directly under the header, updates on every change ("✓ Saved 2 seconds ago · Offline").
- OLP survey appears as a collapsed section labeled "optional" inside the same form, not a separate screen. When expanded, computed `Lebel ng Kahinaan` appears live at the bottom.
- Required-photo chip shows red when missing ("0 of 1 required"). Same chip surfaces in the review screen's warnings.
- Footer: camera button (left), Save Draft (keeps in-progress, exits form), Done (marks `ready_to_upload`, returns to map).

**Review screen** — grouped warnings (missing photos, unfilled features, cost range chosen but not picked, OLP not filled on residential), each with "Go to map" deep link. Failed sync jobs surface here with Retry and Report-Issue actions.

## 10. Error handling & edge cases

**Distance rule.** Haversine GPS→centroid. >50 m = blocking modal with Override/Recenter/Cancel. Override records an `override_reason` on the submission for supervisor review. GPS accuracy >30 m = "weak GPS" banner, allow-but-warn.

**"Does not exist" submissions.** When `does_not_exist=true`, most fields are waived, but **at least one photo is still required** (so supervisor can confirm absence). Frequent abuse case; codifying the photo requirement prevents "skip-by-toggle."

**Auth edge cases.**
- Token expired while offline → user keeps working; refresh happens biometric-gated at next upload.
- Biometric fails or unavailable → password re-entry fallback.
- Password changed on server → 401 during upload → prompt re-login, then retry sync queue.
- Multi-device (same enumerator on two phones) → MVP does not prevent; documented limitation.

**Assignment closed remotely.** Server returns 409 mid-sync → queue halts → blocking screen offers export of pending work as JSON+ZIP bundle.

**Review-screen validation.**
- Blockers: all features `complete` or explicitly skipped-with-remarks; ≥1 photo per complete submission; `ra_9514_type` set for buildings; `width_meters > 0` for roads.
- Warnings: OLP not filled on a residential building; cost estimate chosen but range not picked.

**OLP scoring.** Pure function in `domain/olp/` matching the OLP rubric from the source document. Runs locally on every field change for live preview; keep pure so it can be re-run server-side later. **Spec risk:** rubric transcription accuracy — have an OLP-literate team member validate against 5 hand-scored test cases before Phase 3 is accepted.

## 11. Testing strategy

- **Unit** — domain use cases: OLP scoring, distance calc, completeness validator, retry-backoff calculator. Fast, no Flutter deps.
- **Integration** — Drift DAOs + sync worker with a mocked Supabase client. Assert outbox atomicity (rollback when sync_job insert fails), retry/backoff transitions, 401/409 handling paths, two-phase photo upload ordering.
- **Widget** — auth flow, map tap-interactions, form autosave persistence across simulated app kill (via provider override + disk re-read), review-screen validation surfacing.
- **Manual field-walk** — checklist script run on a real device before pilot: airplane-mode survey → app kill → reopen and verify data → resume → regain connectivity → upload → verify locked state.
- No end-to-end browser automation. Not worth it for a single-app mobile project.

## 12. Phased roadmap

| Phase | Deliverable | Demo state |
|---|---|---|
| **0 — Foundations** | Flutter scaffold + Riverpod, Drift schema + migrations, Supabase project + RLS policies + tables, auth screen, secure storage, biometric unlock, empty home screen | Log in, see empty home. Infra real. |
| **1 — Get Maps + Map** | Assignment bundle download, MapLibre integration, offline tile pack pre-download with progress, color-coded rendering, GPS pin, follow-me toggle, legend | Download an assignment, go offline, open map, see real streets + polygons, GPS pin follows. |
| **2 — Building form + autosave + photos** | Tap-polygon → detail screen, building form with all fields, Drift-backed autosave, 50 m distance check, multi-submission tabs, camera + resize + EXIF + local storage | Walk up to a building offline, fill form, take a photo, kill app, reopen — everything intact. |
| **3 — Road form + OLP + Add-new** | Road form, OLP sub-module with live scoring, long-press-to-add for buildings/roads | Full form matrix; OLP scoring live; can add missing structures. |
| **4 — Sync + Upload + Review** | Outbox sync worker, retry/backoff, two-phase photo upload, 401/409 paths, connectivity-triggered resume, pre-submit review screen, Upload Data flow, assignment-lock state | Offline all day, return online, upload — forms sync first, photos trickle, final "submitted" state. |
| **5 — Polish** | Bilingual labels (EN + TL), dead-job recovery, 409 bundle-export fallback, crash reporting (Sentry), accessibility sweep, field-walk script | Pilot-ready build for BFP volunteers. |

**Dependencies.** 0 and 1 strictly sequential. 2 and 3 can parallelize if enough hands (different forms, no shared state). 4 depends on 2+3. 5 is transverse, touches everything.

**Early risks worth flagging.**

- Offline tile pack size for dense barangays could exceed 300 MB per assignment — measure at end of Phase 1 with a real boundary before committing distribution plan.
- MapLibre offline API quirks on older Android SDKs — 1-day spike in Phase 1 before committing.
- OLP rubric transcription accuracy — gated validation check before Phase 3 is called done.

## 13. Success metrics (from PRD §9) — how this design hits them

- **Data completeness >95% per assignment** ← enforced in Phase 4's review-screen validation; incomplete features block upload.
- **Photo coverage 100% on buildings** ← enforced in Phase 2 (required-photo chip) and Phase 4 (review-screen blocker).
- **Sync reliability >98% within 24 h** ← Phase 4's retry/backoff + connectivity-triggered resume.
- **Crash rate <1% of sessions** ← Phase 5's Sentry + pre-pilot manual testing.
- **Time per structure** ← instrument autosave events in Phase 2 to capture baseline during pilot.

## 14. Open questions from PRD — resolutions in this spec

1. *Server API photo-upload support.* → **N/A.** No existing backend; we're building Supabase Storage path, which natively supports resumable per-photo upload via signed URLs.
2. *Assignment bundle size.* → Measured at end of Phase 1 on a real Cebu City barangay boundary. If it exceeds 300 MB, reconsider tile zoom range or chunked download.
3. *New-structure visibility timing.* → Shown immediately on map as blue pin with `is_new=true`, no wait for server ack.
4. *RA 9514 types source.* → Fetched from Supabase config table on Get Maps, cached locally, hardcoded fallback in app bundle for first-install resilience.
5. *Auth: password vs biometric.* → Supabase email/password for initial sign-in; biometric unlock gates subsequent sessions and upload action.

## 15. Known limitations (documented, not solved)

- Multi-device login for the same enumerator is not prevented.
- Map editing is limited to "add new feature" — no polygon reshape.
- Supervisor approval and messaging live outside the mobile app.
- iOS ships in v2.
- Real-time multi-enumerator collaboration on the same polygon is not supported.
