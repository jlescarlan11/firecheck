# FireCheck Mobile — Phase 1 Design Spec

**Date:** 2026-04-24
**Status:** Draft v1 (brainstorming output)
**Phase:** 1 — Get Maps + offline tile packs + map view
**Parent spec:** `docs/superpowers/specs/2026-04-24-firecheck-mobile-design.md`
**Predecessor phase:** `docs/superpowers/plans/2026-04-24-firecheck-phase-0-foundations.md`

## 1. Summary

Phase 1 delivers the first vertical slice of real field functionality: enumerators log in, tap **Get Maps**, wait ~1–5 minutes while the app downloads their assigned building polygons AND a Mapbox offline tile pack covering their boundary, and then tap **Gather Data** to see a fully offline-capable map of their assignment with color-coded polygons, live GPS position, and a placeholder bottom sheet on polygon tap. No form, no sync worker, no photos — those are Phases 2–4.

## 2. Deviation from parent spec

The parent spec chose **MapLibre GL** for the map renderer. Phase 1 switches to **Mapbox** per user decision. Trade-offs accepted:

- Mapbox requires an account (free tier covers ~50K monthly active users + 200K vector tile loads; ample for a school project).
- Public access token in `.env`, secret token in `~/.gradle/gradle.properties` (gradle-only, never bundled in APK).
- Mapbox SDK bundles telemetry (can be disabled at init), ~5–10 MB heavier APK, more polished Flutter package (`mapbox_maps_flutter` is Mapbox-maintained vs community `maplibre_gl`).

All other parent-spec decisions stand: Flutter, Riverpod, Drift, Supabase, biometric unlock, offline-first, sync outbox, etc.

## 3. Goals & Non-Goals

### Goals
1. First successful download of a real assignment from Supabase into local Drift.
2. Schema v2 migration with FK enforcement + local indexes (Phase 0 → Phase 1 handoff items).
3. Mapbox SDK integrated and rendering on Android with the secret-token build plumbing working end-to-end.
4. Offline tile pack covering the boundary + 200 m buffer at zoom 12–17, downloaded atomically with feature fetch.
5. Map screen with color-coded polygons, dashed boundary, GPS pin, follow-me toggle, legend.
6. Placeholder bottom sheet on polygon tap proving the map → "feature selected" handoff works without committing to Phase 2's form UI.
7. 50-meter distance rule enforced at polygon tap (blocking modal when too far).
8. Seed data (one campaign, one assignment, ten synthetic buildings in Brgy. Tisa, Cebu City) so the demo has something to show.

### Non-Goals
- Actual building attribution form (Phase 2).
- Household survey / OLP (Phase 3).
- Adding new features via long-press (Phase 3).
- Sync queue / upload flow (Phase 4).
- Version reconciliation between local Drift state and server state (Phase 4).
- Camera / photos (Phase 2).
- iOS platform setup.
- Background offline pack downloads (deferred for simplicity — Get Maps is foreground only).

## 4. Stack additions

| Dep | Why |
|---|---|
| `mapbox_maps_flutter` (latest 2.x) | Map rendering + offline region API |
| `geolocator` | GPS stream + permission gate |

### Token handling

- **Public token** (`pk.…`): already in `.env` as `MAPBOX_ACCESS_TOKEN`. Loaded at app start via `dotenv.load()`, then `MapboxOptions.setAccessToken(...)` called alongside `Supabase.initialize(...)`. Bundled in the APK as a Flutter asset — this is the intended use for public tokens.
- **Secret token** (`sk.…`): already in `~/.gradle/gradle.properties` as `MAPBOX_DOWNLOADS_TOKEN`. Read by the Mapbox Android Gradle plugin at build time to authenticate to Mapbox's private Maven repo. Never bundled.
- Android Gradle config: add Mapbox Maven repo to `android/settings.gradle.kts`'s `pluginManagement` block, and add the SDK dependency via `mapbox_maps_flutter`'s instructions.

### Mapbox style + zoom

- Style: `mapbox://styles/mapbox/streets-v12`
- Offline pack zoom range: **z12–z17**
- Region geometry: assignment boundary polygon buffered by **200 meters**

Pack size estimate: ~50–100 MB per barangay-size boundary at this config. Pre-download confirm dialog shown if Mapbox `TileStore.estimateTileRegion(...)` returns > 500 MB. (The SDK supplies the estimate; we don't compute it ourselves.)

## 5. Architecture delta

Builds on Phase 0's layered architecture (Presentation / Domain / Data / Infrastructure). Adds:

- **New cross-cutting platform adapters in `core/`:** `core/mapbox/` (offline pack adapter + Riverpod provider) and `core/location/` (geolocator wrapper + distance math).
- **Two new feature modules:** `features/assignment/` (Get Maps flow) and `features/map/` (map screen + bottom sheet + distance-check use case).
- **Home screen routing changes only:** "Gather Data" and "Get Maps" tiles now open real screens; "Upload Data" still shows its Phase 4 snackbar.

The load-bearing Phase 0 invariant remains: **every write goes to Drift first, the UI reads from Drift streams**. Get Maps is a new source of writes (assignment bundle upsert). The map is a new reactive consumer (watches `features` and `offline_tile_packs`).

## 6. Module structure

```
pubspec.yaml                                      Modify — add mapbox_maps_flutter, geolocator
android/app/src/main/AndroidManifest.xml          Modify — ACCESS_FINE_LOCATION + ACCESS_COARSE_LOCATION
android/settings.gradle.kts                       Modify — pluginManagement mapbox Maven repo

supabase/seed/
  phase_1_demo.sql                                New — mock campaign + assignment + 10 synthetic buildings

lib/
  main.dart                                       Modify — MapboxOptions.setAccessToken(...) at startup
  core/
    db/
      database.dart                               Modify — schemaVersion=2, MigrationStrategy, beforeOpen PRAGMA
      tables/
        features.dart                             Modify — @TableIndex(assignment_id)
        submissions.dart                          Modify — @TableIndex(feature_id)
        photos.dart                               Modify — @TableIndex(submission_id)
        sync_jobs.dart                            Modify — @TableIndex(status, next_retry_at)
        building_attributes.dart                  Modify — @TableIndex(ra_9514_type)
    mapbox/
      mapbox_provider.dart                        New — Riverpod provider + setAccessToken side effect
      offline_pack_adapter.dart                   New — wrapper over Mapbox OfflineManager + progress stream
    location/
      location_service.dart                       New — geolocator wrapper, Stream<Position>
      location_providers.dart                     New — Riverpod providers (permission + stream)
      distance.dart                               New — pure haversine function (domain)
    i18n/
      app_en.arb                                  Modify — Phase 1 strings
      app_tl.arb                                  Modify — Phase 1 strings
  features/
    assignment/
      data/
        assignment_repository.dart                New — fetch from Supabase, upsert to Drift
      domain/
        get_maps_state.dart                       New — sealed state class
      presentation/
        get_maps_screen.dart                      New — progress UI, cancel button, error retry
        assignment_providers.dart                 New — Riverpod providers for get-maps flow
    map/
      data/
        feature_repository.dart                   New — watchFeaturesForAssignment()
      domain/
        distance_check.dart                       New — 50m rule use case
      presentation/
        map_screen.dart                           New — MapWidget + polygon layers + GPS pin
        feature_bottom_sheet.dart                 New — placeholder sheet on tap
        map_providers.dart                        New — Riverpod providers
    home/
      presentation/
        home_screen.dart                          Modify — tiles route to real screens

test/
  core/
    db/
      migration_v1_to_v2_test.dart                New — asserts PRAGMA + indexes
    location/
      distance_test.dart                          New — haversine edge cases
    mapbox/
      offline_pack_adapter_test.dart              New — state transitions with mocked OfflineManager
  features/
    assignment/
      assignment_repository_test.dart             New — mocked Supabase, Drift in-memory
      get_maps_screen_test.dart                   New — widget test with fake repo
    map/
      feature_repository_test.dart                New
      distance_check_test.dart                    New
      map_screen_test.dart                        New — via MapRenderer facade
```

**Boundaries:**
- `core/location/distance.dart` is **pure** — no Flutter, no Mapbox, no async. Haversine math only.
- `features/map/domain/distance_check.dart` is the use case that composes distance + feature + current GPS.
- `MapRenderer` interface in `features/map/presentation/` lets widget tests substitute a fake renderer without needing a GL context for `MapWidget`.

## 7. Data model delta — Schema v2

Phase 1 adds **no new tables**. Bumps `AppDatabase.schemaVersion` from 1 to 2 and adds:

**`MigrationStrategy`:**
- `beforeOpen` (runs on every open): `await customStatement('PRAGMA foreign_keys = ON');`
- `onUpgrade(m, from, to)`: rename column `offline_tile_packs.maplibre_pack_id` → `mapbox_pack_id`; create five indexes (see below).

**Five new indexes** (declared via `@TableIndex(name: '...', columns: {#col})` on table classes so `drift_dev` wires them into `onUpgrade`):

| Table | Column(s) |
|---|---|
| `features` | `assignment_id` |
| `submissions` | `feature_id` |
| `photos` | `submission_id` |
| `sync_jobs` | `status`, `next_retry_at` |
| `building_attributes` | `ra_9514_type` |

**Column rename** on `offline_tile_packs`: `maplibre_pack_id` → `mapbox_pack_id`. Single ALTER in `onUpgrade`.

### New query surface

**`FeatureRepository`**
- `Stream<List<Feature>> watchFeaturesForAssignment(String assignmentId)` — drives the map
- `Future<Feature?> getFeature(String id)` — drives bottom sheet lookup

**`AssignmentRepository`**
- `Future<Assignment?> getCurrentAssignment()`
- `Stream<Assignment?> watchCurrentAssignment()` — drives home
- `Future<void> upsertAssignmentBundle({ ... })` — transactional: assignment + features + ra_9514 rows in one Drift transaction. `ra_9514_types` fetched from the server's config table; if empty (as in Phase 1's seed), the app falls through to the hardcoded RA 9514 fallback list (parent spec §3, table `ra_9514_types`). Not a failure case — Phase 1 doesn't need the list, only Phase 3 does.

**`OfflineTilePackRepository`**
- `Stream<OfflineTilePack?> watchForAssignment(String assignmentId)`
- `Future<void> upsert({required String assignmentId, String? mapboxPackId, String regionBoundsGeojson, ...})`
- `Future<void> updateProgress(String id, int downloadedBytes, int totalBytes)`
- `Future<void> markReady(String id)`
- `Future<void> markError(String id, String message)`

## 8. Get Maps flow

### State machine

`features/assignment/domain/get_maps_state.dart`:

```
sealed GetMapsState
  └ Idle
  └ FetchingFeatures
  └ DownloadingTiles(downloadedBytes, totalBytes)
  └ Ready(featureCount, totalBytes)
  └ Cancelled
  └ GetMapsError(Failure)
```

Transitions are linear per run. Terminal states (Ready / Cancelled / GetMapsError) require re-tapping Get Maps to start a new run from Idle.

```
Idle
  ↓ (user tap + network check OK)
FetchingFeatures                        ← Supabase fetch of assignment + features + ra_9514_types
  ↓ on success                            on NetworkFailure / ServerRejected → GetMapsError
DownloadingTiles(0, n)                  ← Mapbox offline region creation
  ↓ progress updates                      on user Cancel → Cancelled
DownloadingTiles(k, n)                    on Mapbox error → GetMapsError
  ↓ on complete
Ready
```

### Unified progress

```
overall = state is FetchingFeatures ? 0.05
        : state is DownloadingTiles ? 0.05 + 0.95 * (downloaded/total)
        : state is Ready ? 1.00
        : 0
```

### Cancel semantics

- `MapboxOfflinePackAdapter.cancel(packId)` → Mapbox `TileStore.cancel(...)`
- Transactional Drift write: `offline_tile_packs.status = 'error'`, `assignments.status` reset to `assigned`, features kept (overwritten on next run).
- State → `Cancelled`. Mapbox's partial cached tiles stay in its own store; next Get Maps resumes at no cost per-tile thanks to the SDK's native dedup. We don't surface this as user-visible "resume."

### Error matrix

| Failure | User sees | Recovery |
|---|---|---|
| No internet at start | Snackbar on home "You need internet to download maps." | Retry when connected |
| Supabase timeout | `GetMapsError(NetworkFailure)` screen | Retry button |
| Supabase 401 | Existing Phase 0 auth-expired handling | Re-login, restart Get Maps |
| No assignment for this enumerator | `GetMapsError(ServerRejectedFailure(404))` | Terminal — "Contact supervisor" |
| Mapbox download failure | `GetMapsError` with message | Retry button |
| Estimated size > 500 MB | Pre-download confirm dialog | Confirm or cancel |

### Screen composition

Single `GetMapsScreen` with three visual states (not three screens):

1. **Initial** — explainer + "Start download" button + back arrow.
2. **In progress** — progress bar, label ("Fetching buildings…" → "Downloading map tiles…"), downloaded/total in MB, Cancel button.
3. **Done** — checkmark + "Ready to gather data" + "Open map" button (routes to `/map`) + "Back to home".

### What Get Maps does NOT do in Phase 1
- No background download (foreground only).
- No "already downloaded" detection (silently re-fetches; Mapbox dedup makes it cheap).
- No campaign selection UI (assumes one active assignment per enumerator).

## 9. Map screen

Entry point: "Gather Data" tile on home. Route `/map`.

### Layout (matches mockup in spec brainstorming session)

- Full-bleed `MapWidget` from `mapbox_maps_flutter` with Streets v12 style served from the cached offline pack.
- Dashed orange boundary (`#d97706`, 2dp stroke, no fill) over the assignment boundary polygon.
- Color-coded survey polygons per status:
  - `unfilled` → red fill `#c53030 @ 0.35`, stroke `#c53030`
  - `in_progress` → yellow fill `#b7791f @ 0.40`
  - `complete` → green fill `#276749 @ 0.40`
  - `is_new = true` → blue point pin `#3b82f6` with white border
- GPS pin via Mapbox `LocationComponentPlugin`, driven by `geolocator` stream; accuracy halo is the SDK default blue circle.
- Top app bar: back arrow, title `"Gather Data"`, subtitle `"{completedCount} of {totalCount} · {assignmentName}"`, offline badge when disconnected.
- Corner legend (top-right): dot + label per status.
- Bottom toolbar: `Follow me` toggle (on by default, off when user pans; tap to re-engage), `+ New Feature (P3)` disabled pill, recenter button.
- Two separate `PolygonAnnotationManager`s: one for assignment features, one for boundary — so their paint properties stay isolated.

### Tap flow

On polygon tap:

1. Distance check via `distance_check.dart` use case: haversine between GPS and feature centroid.
2. If within 50 m → bottom sheet slides up showing:
   - Feature type icon + `"Building · Unfilled"` (or current status)
   - Short-hash ID, type, status, is_new flag
   - `"{n} m away ✓"` line
   - Tan-tinted "Form coming in Phase 2" banner
   - Close button
3. If more than 50 m away → blocking modal: "Feature too far — you're {n}m away. Map policy requires ≤50m." Buttons: **Continue anyway** / **Cancel**. Continue-anyway opens the sheet anyway (Override recording is Phase 2's concern).
4. Tapping inside boundary but not on a polygon → no-op.
5. Long-press → reserved for Phase 3 (no-op in Phase 1).

### Error / edge cases

| Situation | Behavior |
|---|---|
| Location permission denied | Top banner: "Location off — tap to enable" → opens system settings |
| Permission deferred | Banner: "Waiting for GPS…"; polygons still render |
| No cached offline pack | Modal "This assignment hasn't been downloaded. Go to Get Maps." → routes back to home |
| GPS accuracy > 30 m | Faint banner "Weak GPS signal"; allow interactions |
| Stale server data | **NOT detected in Phase 1** — Phase 4 adds version checking |

## 10. Seed data

File: `supabase/seed/phase_1_demo.sql`. Applied once with `psql` or Supabase SQL editor.

Contents (single transaction):

1. **One campaign** — UUID `00000000-0000-0000-0000-0000000000c1`, name `"FireCheck Phase 1 Demo"`.
2. **One assignment** — assigned to enumerator `41bc0780-fa43-411c-93f4-4db926cc1ded` (existing `admin@admin.com` user), boundary ~200 m × 150 m rectangle centered on `(10.31810, 123.88270)` in Brgy. Tisa, Cebu City, status `assigned`.
3. **Ten building features** — synthetic 2×5 grid inside boundary, each ~20 m × 15 m, spaced ~35 m apart. `feature_type = 'building'`, `is_new = false`, PostGIS `geography(Polygon, 4326)`.

Re-runnable via `insert ... on conflict (id) do nothing`. Clean reset: `DELETE FROM assignments WHERE campaign_id = '...';` (FK cascade handles features).

Seed does NOT seed `ra_9514_types`, `submissions`, or `photos`. Those come later (Phase 3 for ra_9514_types; from running the app for the rest).

## 11. Testing strategy

### Unit (fast, no Flutter deps)
- `distance_test.dart` — haversine against known-answer pairs (Manila↔Cebu, polar, antipodal, same-point).
- `GetMapsState` transitions — direct instantiation, no mocks.

### Integration (Drift in-memory + mocked Supabase)
- `migration_v1_to_v2_test.dart` — open DB at v1, verify FK pragma is 0, upgrade, verify FK pragma is 1, verify all five indexes exist via `sqlite_master`.
- `assignment_repository_test.dart` — `upsertAssignmentBundle` transactionality: if a mid-bundle feature insert fails, assignment row rolls back.
- `feature_repository_test.dart` — `watchFeaturesForAssignment` reactive semantics.
- `offline_pack_adapter_test.dart` — state transitions with mocked Mapbox `OfflineManager`.
- `offline_tile_pack_repository_test.dart` — lifecycle (downloading → progress → ready).

### Widget
- `get_maps_screen_test.dart` — three visual states, provider override for `GetMapsState`, progress assertions, cancel button visibility.
- `map_screen_test.dart` — behind `MapRenderer` facade with fake implementation; tests bottom-sheet appearance, distance modal, offline badge.
- `feature_bottom_sheet_test.dart` — renders fake Feature correctly.

### Manual field-walk checklist
1. Apply `supabase/seed/phase_1_demo.sql`.
2. Fresh install → login → tap Get Maps → download completes.
3. Airplane mode.
4. Tap Gather Data → map renders offline with tiles + polygons.
5. Walk to within 10 m of one polygon → tap → bottom sheet shows `~10 m away ✓`.
6. Walk >50 m → tap → distance modal.
7. Kill app → reopen → land on home → tap Gather Data → map still works.

### Not tested
- Actual Mapbox tile download (mocked at adapter boundary).
- GPS stream fidelity (geolocator's own tests).
- `MapWidget` pixel rendering (Mapbox's concern).

## 12. Phase 1 demo state

After running `supabase/seed/phase_1_demo.sql` and completing Phase 1 implementation:

1. Log in as `admin@admin.com` / `admin123`.
2. Home shows "0 of 10 features" (10 from seed, 0 have submissions yet).
3. Tap Get Maps → progress bar runs to 100% → "Ready to gather data."
4. Tap Open map (or Gather Data on home) → map shows Brgy. Tisa streets from offline cache, 10 red polygons, dashed orange boundary, GPS pin tracking current position.
5. Tap a polygon → bottom sheet with metadata and "Form coming in Phase 2" banner.
6. Turn off wifi + cellular → everything still works because tiles + data are local.

## 13. Known deferrals (out of Phase 1, captured for later phases)

| Item | Target phase | Why deferred |
|---|---|---|
| Building form | Phase 2 | Core focus of Phase 2 |
| Photo capture | Phase 2 | Pairs with form |
| Add new feature (long-press) | Phase 3 | Needs form working first |
| OLP household survey | Phase 3 | Own module |
| Sync outbox | Phase 4 | Needs form writes to sync |
| Version reconciliation (map screen) | Phase 4 | Part of sync design |
| Background offline pack download | Phase 4 | Pairs with sync worker |
| Upload flow | Phase 4 | End of cycle |
| Crash reporting (Sentry) for new flows | Phase 5 | Polish pass |
| iOS platform setup | v2 | Android-first MVP |

## 14. Success criteria for Phase 1

- Fresh install → login → Get Maps → Map → tap polygon → see bottom sheet. End-to-end in under 10 minutes on wifi.
- App usable offline after Get Maps completes.
- `flutter analyze` clean, all Phase 0 and Phase 1 tests passing.
- Commit under a `phase-1-map` tag at the end.
