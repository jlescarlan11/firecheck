# FireCheck Mobile — Reshape Building Polygon Design Spec

**Date:** 2026-04-29
**Status:** Draft v1 (brainstorming output)
**Story:** US-9 — As an enumerator, I want to reshape an existing building polygon by moving, adding, or removing vertices, so that I can correct footprints that are inaccurate on the ground.
**Parent spec:** `docs/superpowers/specs/2026-04-24-firecheck-mobile-design.md`
**Related:**
- `docs/superpowers/specs/2026-04-24-firecheck-phase-1-design.md` (map screen architecture)
- `docs/superpowers/specs/2026-04-28-recenter-map-design.md` (sibling story; established `CameraTarget`, `MapRenderer` interface, analytics plumbing, override-reason dialog reuse pattern)
- `docs/superpowers/specs/2026-04-28-map-zoom-buttons-design.md` (sibling story; established `onCameraChanged` test seam, button-stack layout)

This story expands map-editing scope. Master spec §15 and Phase 4a/4b explicitly defer polygon reshape to "v2+"; this spec implements that capability while preserving the documented limitation that reshape is **building polygons only** (roads/LineStrings remain out of scope).

## 1. Summary

Add a **reshape building polygon** flow to the FireCheck map. An enumerator long-presses an existing building polygon to open an action sheet with `Open form / Reshape / Cancel`. Tapping `Reshape` triggers the existing 50 m distance check (with the existing override-reason dialog), then enters a dedicated edit mode: a top banner replaces normal chrome, vertex handles + midpoint indicators render over the polygon, and the user can move, add, and remove vertices with live validation feedback. Save commits the new geometry locally with an audit revision row and queues a sync job; cancel discards everything in memory.

After this ships:

1. Long-press on any building polygon shows a `Open form / Reshape / Cancel` action sheet (when add-mode is off).
2. `Reshape` runs the same 50 m distance gate as form-open, with override-reason support.
3. Edit mode shows a blue top banner (`Cancel | Reshape • N edits | Save`) above the map and white circular handles on every vertex with hollow blue midpoint dots between vertices.
4. Drag a handle to move a vertex; touch-and-drag a midpoint to pull a new vertex out of an edge; long-press a handle → confirm dialog → vertex removed.
5. Self-intersecting edges render red live during drag.
6. Save validates (≥3 unique vertices, non-zero area, non-self-intersecting, all vertices inside boundary, no zero-length edges); rejects with a snackbar if any rule fails; commits + queues sync if all pass.
7. Edits cannot be made when the assignment is locked. Edits are allowed even if the building's submission has already uploaded — geometry corrections are independent of survey state.
8. Server applies the update via a new RPC with optimistic concurrency on the previous geometry; revision row written for audit (with optional override reason).

## 2. Scope

### In scope

- **`ReshapeModeController`** — Riverpod `Notifier` holding the in-memory working copy, undo stack, dirty flag, and live `selfIntersects` state. Lives at `lib/features/map/reshape/presentation/reshape_mode_controller.dart`.
- **Reshape UI** — top banner, vertex handles (14×14 white circle, blue ring; 44×44 hit area), midpoint handles (10×10 hollow blue dot; 44×44 hit area), action sheet, remove-confirm dialog. All under `lib/features/map/reshape/presentation/`.
- **Reshape overlay** — absolute-positioned `Stack` of handles, projected to screen pixels via new lat/lng ↔ screen-px helpers exposed by `MapRenderer`.
- **`MapRenderer.build()` signature additions** — `onPolygonLongPress(Feature)` callback, `reshapeWorkingPolygonGeojson?` (overrides the persisted polygon during edit), `reshapeInvalidEdgeGeojson?` (red overlay for live self-intersection), and projection helpers exposed via callback so the overlay can position handles. `MapboxMapRenderer` implements via the native long-press hit-test + `coordinateForPixel`/`pixelForCoordinate`. `FakeMapRenderer` adds `simulatePolygonLongPress` and a fake projection (identity within bounds).
- **`PolygonValidator`** — pure-Dart validator with five rules (`tooFewVertices`, `zeroOrNegativeArea`, `selfIntersection`, `vertexOutsideBoundary`, `zeroLengthEdge`). Lives at `lib/core/geo/polygon_validator.dart`. Returns `intersectingEdges` for live red-edge feedback.
- **`FeatureGeometryRevisions` Drift table** — append-only audit + outbox. Same shape on the server.
- **`update_feature_geometry` RPC** (Supabase migration `011`) — applies the geometry update with optimistic concurrency on the prior geometry (`ST_Equals`); inserts a server-side revision row in the same transaction. RLS scoped to assignment ownership.
- **Sync** — new `entity_type='feature_geometry_update'`. New `SyncApi.uploadFeatureGeometryUpdate`. Wired into `SyncWorker` with the existing retry/backoff/dead-letter machinery.
- **Lock interactions** — assignment locked → reshape entry blocked (action sheet item disabled). Building has uploaded submissions → reshape allowed. Locked-while-dirty → "Assignment was closed" non-dismissable banner; edits discarded.
- **Mutual exclusion with add-mode** — entry is gated on `!_addModeActive`. The bottom add-feature pill is hidden while reshape is active.
- **Analytics** — four events: `map.reshape.entered`, `map.reshape.cancelled`, `map.reshape.completed`, `map.reshape.validation_failed`. Routed through the existing `analyticsServiceProvider`.
- **i18n** — ~12 new ARB keys (action sheet ×3, banner ×2, remove dialog ×3, error snackbars ×4) in `app_en.arb` and `app_tl.arb`.

### Out of scope

- Reshape on `is_new` point-pin features (those aren't polygons yet — separate story when they become polygons).
- Reshape on roads (LineStrings). Same architecture would apply; separate story.
- Splitting one polygon into multiple polygons.
- Merging multiple polygons into one.
- Bulk reshape across multiple buildings.
- Snapping (to GPS, to nearby vertices, to orthogonal angles) — premature without field feedback; can be added without changing this design.
- Real-time multi-enumerator collaboration on the same polygon (master spec §15 confirms v2+).
- "Save draft" of an in-progress reshape across app kills — geometry edits are short atomic operations; persisting partial state would complicate the undo stack and surface stale half-edits. Explicit AC choice.
- Showing revision history on the device — supervisor sees it server-side.
- Pessimistic locking (server marks feature "in edit"). Only one writer (mobile) per assignment by data model.
- Auto-merge on `geometry_conflict` — fail loud and force the user to start a new reshape session.

## 3. Architecture

### Files added

```
lib/features/map/reshape/
  presentation/
    reshape_mode_controller.dart       # in-memory working copy, undo stack, dirty flag,
                                       # live selfIntersects flag
    reshape_providers.dart             # Riverpod providers wiring the controller
    reshape_banner.dart                # top banner: Cancel | "Reshape • N edits" | Save
                                       # plus an Undo chip below
    reshape_action_sheet.dart          # showReshapeActionSheet() — Open form / Reshape /
                                       # Cancel; "Reshape" disabled when assignment locked
    reshape_remove_confirm_dialog.dart # showReshapeRemoveConfirm() — native AlertDialog;
                                       # confirm disabled when ring would drop below 3
    vertex_handle.dart                 # 14×14 white circle, blue ring; 44×44 hit area
    midpoint_handle.dart               # 10×10 hollow blue dot; 44×44 hit area
    reshape_overlay.dart               # absolute-positioned Stack of handles, projected
                                       # via the renderer's lat/lng → screen-px helper

  data/
    feature_geometry_revisions_repository.dart
                                       # writes revision row + corresponding sync_jobs row
                                       # in a single Drift transaction; provides the
                                       # row-by-id lookup SyncWorker uses to fetch the
                                       # payload for the 'feature_geometry_update' branch

lib/core/geo/
  polygon_validator.dart               # 5 rules; pure Dart; O(n²) self-intersection

lib/core/db/tables/
  feature_geometry_revisions.dart      # Drift table

supabase/migrations/
  011_feature_geometry_updates.sql     # feature_geometry_revisions table +
                                       # update_feature_geometry RPC + RLS policies

test/features/map/reshape/...          # widget tests (Section 9)
test/core/geo/polygon_validator_test.dart
test/core/db/feature_geometry_revisions_test.dart
test/core/sync/feature_geometry_update_sync_test.dart
```

### Files changed

```
lib/features/map/presentation/
  map_screen.dart                      # add long-press-on-polygon path → action sheet;
                                       # mount ReshapeBanner + ReshapeOverlay when
                                       # ReshapeMode is active; hide add-mode pill while
                                       # reshape is active
  map_renderer.dart                    # MapRenderer.build() gains:
                                       #   - onPolygonLongPress(Feature) callback
                                       #   - reshapeWorkingPolygonGeojson?
                                       #   - reshapeInvalidEdgeGeojson?
                                       #   - projectionListener? (lat/lng ↔ screen-px)
                                       # FakeMapRenderer adds simulatePolygonLongPress
                                       # and an identity-within-bounds projection

lib/core/db/database.dart              # register FeatureGeometryRevisions; bump
                                       # schemaVersion + onUpgrade migration

lib/core/sync/data/sync_api.dart       # add uploadFeatureGeometryUpdate(revision)
lib/core/sync/data/supabase_sync_api.dart
                                       # implement RPC call with prev_geometry param;
                                       # 409 + 'geometry_conflict' → permanent failure
lib/core/sync/data/fake_sync_api.dart  # in-memory recording for tests
lib/core/sync/worker/sync_worker.dart  # new entity_type='feature_geometry_update' branch

lib/core/i18n/
  app_en.arb, app_tl.arb               # ~12 new keys (action sheet ×3, banner ×2,
                                       # remove dialog ×3, error snackbars ×4)
```

### State machine — `ReshapeModeController`

```
       ┌──────────┐
       │ inactive │ ◄─── default
       └─────┬────┘
             │ enterReshape(feature, overrideReason?)
             ▼
       ┌──────────┐  edit (move/add/remove)   ┌──────────┐
       │  clean   │ ─────────────────────────▶│  dirty   │
       └─────┬────┘                            └────┬─────┘
             │ cancel                               │ undo→clean OR more edits
             ▼                                      ▼ save
       ┌──────────┐                            ┌──────────────┐
       │ inactive │                            │  validating  │
       └──────────┘                            └─────┬────────┘
                                                     │ pass→commit→inactive
                                                     │ fail→stay dirty + snackbar
```

`LngLat` throughout this spec is the value type `({double lng, double lat})` (Dart 3 named record). No new class file is required.

```dart
class ReshapeModeState {
  final Feature? originalFeature;        // captured at enterReshape; never mutated
  final List<List<LngLat>> workingRings; // mutable working copy (outer + holes)
  final List<ReshapeOp> undoStack;       // for the Undo chip in the banner
  final bool selfIntersects;             // live validity flag for red-edge rendering
  final bool saving;                     // disables Save button during commit
  final String? overrideReason;          // captured at the 50m gate, written into
                                         // feature_geometry_revisions on save
}

sealed class ReshapeOp {
  const ReshapeOp();
}
class Move   extends ReshapeOp { final int ringIdx, vertexIdx; final LngLat prev, next; }
class Add    extends ReshapeOp { final int ringIdx, vertexIdx; final LngLat lngLat; }
class Remove extends ReshapeOp { final int ringIdx, vertexIdx; final LngLat removed; }
```

Undo replays the inverse op and pops the stack. The undo stack is unbounded in memory (≤100 vertices × a single session ≈ a few hundred bytes per op).

### Mutual exclusion

While reshape is active:
- The bottom add-feature pill is **hidden** (banner takes the spotlight). Reshape and add-mode are mutually exclusive.
- Recenter / zoom buttons stay visible — reshape needs them; pinch + button zoom both still work.
- Polygon tap handlers are **disabled** for all polygons; the polygon being reshaped is non-tappable (handles take all gestures).

## 4. Data model

### Local Drift table — `feature_geometry_revisions`

```dart
@TableIndex(name: 'fgr_feature_id_idx',  columns: {#featureId})
@TableIndex(name: 'fgr_sync_status_idx', columns: {#syncStatus})
class FeatureGeometryRevisions extends Table {
  TextColumn     get id              => text()();           // uuid v4 (client-side)
  TextColumn     get featureId       => text()();           // FK → features.id
  TextColumn     get prevGeojson     => text()();           // captured at enterReshape
  TextColumn     get newGeojson      => text()();           // committed working copy
  TextColumn     get editedBy        => text()();           // enumerator id
  DateTimeColumn get editedAt        => dateTime()();       // client wall clock
  TextColumn     get overrideReason  => text().nullable()();// non-null iff 50m gate overridden
  TextColumn     get syncStatus      => text().withDefault(const Constant('pending'))();
                                                            // pending|ready_to_upload|uploaded|failed
  DateTimeColumn get createdAt       => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

`syncStatus` mirrors `submissions.sync_status` semantics. The `sync_jobs` row created in the same transaction carries `entity_type='feature_geometry_update'`, `entity_id=revision.id`. `features.geometry_geojson` is updated to `newGeojson` in the same transaction so the map reflects the change immediately.

### Server-side schema — `011_feature_geometry_updates.sql`

```sql
create table public.feature_geometry_revisions (
  id              uuid primary key,
  feature_id      uuid not null references public.features(id) on delete cascade,
  edited_by       uuid references public.enumerators(id) on delete set null,
  prev_geometry   geography(Geometry, 4326) not null,
  new_geometry    geography(Geometry, 4326) not null,
  edited_at       timestamptz not null,
  override_reason text,
  created_at      timestamptz not null default now()
);

create index on public.feature_geometry_revisions (feature_id);
create index on public.feature_geometry_revisions (edited_by);

alter table public.feature_geometry_revisions enable row level security;

create policy fgr_enum_insert on public.feature_geometry_revisions
  for insert with check (
    exists (
      select 1 from public.features f
      join public.assignments a on a.id = f.assignment_id
      where f.id = feature_id and a.enumerator_id = auth.uid()
    )
  );
create policy fgr_enum_select on public.feature_geometry_revisions
  for select using (
    exists (
      select 1 from public.features f
      join public.assignments a on a.id = f.assignment_id
      where f.id = feature_id and a.enumerator_id = auth.uid()
    )
  );

create or replace function public.update_feature_geometry(
  p_revision_id    uuid,
  p_feature_id     uuid,
  p_prev_geojson   text,
  p_new_geojson    text,
  p_edited_at      timestamptz,
  p_override_reason text
) returns void
language plpgsql
security definer
as $$
declare
  v_current geography;
  v_prev    geography;
  v_new     geography;
begin
  if not exists (
    select 1 from public.features f
    join public.assignments a on a.id = f.assignment_id
    where f.id = p_feature_id and a.enumerator_id = auth.uid()
  ) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  v_prev := st_geogfromgeojson(p_prev_geojson);
  v_new  := st_geogfromgeojson(p_new_geojson);

  select geometry into v_current from public.features
    where id = p_feature_id for update;

  -- Optimistic concurrency: server's current geometry must match the prev_geometry
  -- the client based its edit on. ST_Equals is exact equality; a future story can
  -- relax to ST_Within with epsilon if false-conflicts surface.
  if not st_equals(v_current::geometry, v_prev::geometry) then
    raise exception 'geometry_conflict' using errcode = 'P0001';
  end if;

  insert into public.feature_geometry_revisions
    (id, feature_id, edited_by, prev_geometry, new_geometry, edited_at, override_reason)
  values
    (p_revision_id, p_feature_id, auth.uid(), v_prev, v_new, p_edited_at, p_override_reason);

  update public.features set geometry = v_new where id = p_feature_id;
end;
$$;
```

Client mapping for the RPC's PostgreSQL error codes:
- `geometry_conflict` (`P0001`) → permanent sync failure (`syncStatus='failed'`, `sync_job.status='dead'`); UI surfaces "Reshape was rejected — geometry was changed by supervisor. Re-open and reshape again to retry."
- `forbidden` (`42501`) → permanent failure (auth went stale or RLS denied); same dead-letter path with a different message.
- `22023` / `XX000` (malformed geometry from `ST_GeogFromGeoJSON`) → permanent failure. Should not happen — Drift transaction validates serializability — but if it does, fail loud, not silent.

### Working-copy GeoJSON conventions

- Outer ring stored CCW; holes CW. We don't enforce on input (the existing seed and Mapbox both produce both orderings); we **do** normalize on commit so `prev_geometry` and `new_geometry` are comparable for `ST_Equals`.
- First and last vertex always coincident (closed ring). Working copy stores the open form (no duplicate end vertex) and serializes the close on commit.
- Coordinates: `[lng, lat]` order (GeoJSON standard, matches existing `geometryGeojson` storage).

## 5. Validation

`lib/core/geo/polygon_validator.dart`. Pure Dart, no dependencies. One public function:

```dart
PolygonValidationResult validateBuildingPolygon(
  List<List<LngLat>> rings, {
  required String boundaryGeojson,
});

class PolygonValidationResult {
  final bool valid;
  final PolygonValidationError? error;        // null when valid
  final List<EdgeIndex>? intersectingEdges;   // populated when error == selfIntersection
}

// Identifies a pair of edges in the working outer ring that mutually intersect.
// `aStart` and `bStart` index into workingRings[0]; the edge runs from index N
// to (N+1) % ringLength.
typedef EdgeIndex = ({int aStart, int bStart});

enum PolygonValidationError {
  tooFewVertices,        // <3 unique vertices on outer ring
  zeroOrNegativeArea,    // shoelace area ≈ 0 (1e-12 sq-degrees)
  selfIntersection,      // any non-adjacent edges intersect (open segments only)
  vertexOutsideBoundary, // any vertex fails pointInPolygonGeojson(boundary)
  zeroLengthEdge,        // adjacent vertices coincident (epsilon ≈ 1e-9 degrees)
}
```

Rules run in declared order; first failure short-circuits.

**Self-intersection algorithm:** O(n²) pairwise non-adjacent segment intersection using the standard CCW orientation test. At ≤100 vertices, ≤4,950 pair tests per validation tick. Easily runs at 60 fps on a mid-tier Android device. The validator returns the indices of all intersecting edge pairs so the renderer can paint them red.

**Live vs save-time:**
- During drag (every frame the dragged vertex moves): only run rule 3 (`selfIntersection`). Cheap; gives instant red-edge feedback.
- On Save: run all five rules in order. Failure → snackbar with rule-specific i18n message; mode stays open.

**Boundary failure is a hard block.** No override path for `vertexOutsideBoundary` — the boundary defines what data the enumerator is authorized to capture. The 50 m distance gate (an authorization-adjacent UX rule) has an override; the boundary check (a data-integrity rule) does not.

## 6. Orchestration & gestures

### Long-press hit-test entry

`MapRenderer.build()` gains an `onPolygonLongPress(Feature)` callback. `MapboxMapRenderer` wires this through:
- `onLongTapListener` checks `addModeActive` first (existing path); if true, the long-press is consumed by add-mode placement.
- If `addModeActive` is false, the renderer queries the feature manager for any polygon under the tap point. If a hit, `onPolygonLongPress(feature)` fires. If a miss, no-op.

`_MapScreenState._handlePolygonLongPress` then:
1. If assignment locked → show snackbar "Assignment is closed; reshape unavailable." and exit.
2. Show action sheet via `showReshapeActionSheet(feature)`. Three items: `Open form`, `Reshape`, `Cancel`.
3. On `Open form` → existing `_handleFeatureTap` path.
4. On `Reshape` → enter reshape flow (next).

### Distance gate on `Reshape`

Mirrors the existing `_handleFeatureTap` path:
1. Compute haversine distance from current GPS to feature centroid.
2. If <30 m accuracy → show weak-GPS banner (existing `override_reason_dialog.dart` pattern).
3. If >50 m → open override-reason dialog. Cancel exits flow; confirm captures the reason string.
4. On pass (or override), call `ReshapeModeController.enterReshape(feature, overrideReason)`.

### Edit-mode gestures

| Gesture | Outcome |
|---|---|
| Tap-and-drag a vertex handle | `Move` op; live `selfIntersects` recheck per drag tick; release commits the op to the working ring + undo stack. |
| Touch-and-drag a midpoint handle | `Add` op fires immediately at touch-down, inserting a new vertex at the midpoint position; vertex enters drag mode in the same gesture (one continuous touch). Release commits. |
| Long-press a vertex handle | `showReshapeRemoveConfirm` (native AlertDialog). Confirm button **disabled** when working ring has 3 vertices. Confirm → `Remove` op. Cancel → no-op. |
| Tap Undo chip in banner | Pop one op from undo stack; replay inverse. |
| Tap Cancel in banner | Discard `ReshapeModeController` state; return to inactive. No DB write. |
| Tap Save in banner | Run all five rules. Pass → commit transaction + sync job + analytics + exit. Fail → snackbar; stay in mode. |

### Save commit — Drift transaction

```dart
Future<void> saveReshape(ReshapeModeState state) async {
  await _db.transaction(() async {
    final revisionId = const Uuid().v4();
    final newGeojson = serializeRings(state.workingRings);
    final prevGeojson = state.originalFeature!.geometryGeojson;

    await _db.update(_db.features)
      ..where((t) => t.id.equals(state.originalFeature!.id))
      ..write(FeaturesCompanion(geometryGeojson: Value(newGeojson)));

    await _db.into(_db.featureGeometryRevisions).insert(
      FeatureGeometryRevisionsCompanion.insert(
        id: revisionId,
        featureId: state.originalFeature!.id,
        prevGeojson: prevGeojson,
        newGeojson: newGeojson,
        editedBy: editedBy,
        editedAt: DateTime.now(),
        overrideReason: Value(state.overrideReason),
        syncStatus: const Value('ready_to_upload'),
        createdAt: DateTime.now(),
      ),
    );

    await _db.into(_db.syncJobs).insert(
      SyncJobsCompanion.insert(
        id: const Uuid().v4(),
        entityType: 'feature_geometry_update',
        entityId: revisionId,
        createdAt: DateTime.now(),
      ),
    );
  });
}
```

## 7. Sync mechanics

```
[Save tap]
   │
   ▼
[Drift transaction, atomic]
   │   - update features.geometry_geojson = newGeojson
   │   - insert feature_geometry_revisions row (syncStatus='ready_to_upload')
   │   - insert sync_jobs row (entity_type='feature_geometry_update',
   │                           entity_id=revision.id, status='pending')
   ▼
[SyncWorker picks up job]
   │
   ▼
[SyncApi.uploadFeatureGeometryUpdate(revision)]
   │   POST /rpc/update_feature_geometry
   │   body: { p_revision_id, p_feature_id, p_prev_geojson, p_new_geojson,
   │           p_edited_at, p_override_reason }
   │
   ├─ 2xx          → revision.syncStatus='uploaded'; sync_jobs.status='success'
   ├─ 401          → reauth path (existing) → retry
   ├─ 409 + 'geometry_conflict'
   │                → sync_jobs.status='dead'; revision.syncStatus='failed';
   │                  surfaces via existing sync-error surfacer
   ├─ 4xx (other)  → permanent failure (dead-letter)
   └─ 5xx / network → transient; existing exponential backoff
```

## 8. Edge cases

- **App killed mid-edit (no Save).** Working copy lives only in `ReshapeModeController` memory. Drift untouched. Restart → polygon unchanged. **No "draft" preservation by design** — explicit AC choice.
- **App killed after Save, before sync.** Local DB has new geometry + revision row + pending `sync_job`. Map renders the new geometry. `SyncWorker` picks up the job on next launch / next connectivity window.
- **Connectivity drops mid-upload.** Standard `SyncWorker` retry path; revision row stays at `syncStatus='ready_to_upload'`.
- **User long-presses a polygon while in add-mode.** Action sheet does *not* open; long-press is consumed by add-mode placement (existing path at `map_screen.dart:193-207`). Reshape entry is gated on `!_addModeActive`.
- **User long-presses an `is_new` point pin (blue).** Action sheet does not open — no polygon under the press. No-op.
- **User long-presses outside any polygon.** No-op.
- **Assignment becomes locked while in edit mode.** `ReshapeModeController` watches `isAssignmentLockedProvider`. On lock event: if `clean`, exit silently to inactive. If `dirty`, show a non-dismissable banner ("Assignment was closed by supervisor — your edits cannot be saved") with an `Exit` button. Edits are discarded.
- **GPS deteriorates between `Reshape` tap and Save.** No re-check; the 50 m gate is one-shot at entry. Aligns with the form flow.
- **User reshapes, saves, then reshapes again before sync.** Two revision rows + two sync jobs, both pending. Server applies them in order; the second's `prev_geometry` matches the first's `new_geometry`, so optimistic concurrency holds.
- **Underlying Drift row stream emit during edit (e.g., status flips `in_progress → complete`).** `originalFeature` reference is captured at `enterReshape` time. Working copy is unaffected. Save still uses the *captured* `prevGeojson`. Status updates flow through normally because the controller tracks geometry only.
- **User pinches/zooms while a vertex is mid-drag.** Renderer reprojects all handles every camera change. Drag continues — the in-flight handle's underlying lat/lng is preserved; only its screen position is recomputed.
- **Save with vertices outside the assignment boundary.** `vertexOutsideBoundary` returned. Snackbar: "Some vertices are outside the assignment area." Edit mode stays open. No override path.
- **Many edits in one session.** Undo stack is unbounded in memory. ≤100 vertices in a single session ≈ a few hundred bytes per op. No persistence.
- **Server returns `geometry_conflict`.** Sync job dies; revision row marked `failed`. UI surfacer shows "Reshape was rejected — geometry was changed by supervisor. Re-open and reshape again to retry." User starts a fresh reshape session; the failed revision row is dropped from the active set (its `prev_geojson` is no longer accurate). No auto-merge.
- **Malformed GeoJSON at the server.** Permanent failure, dead-letter. Should not happen — Drift transaction validates serializability — but if it does, fail loud, not silent.

## 9. Testing strategy

Tests follow the existing FireCheck pattern: pure-Dart unit tests for logic, widget tests for UI with `FakeMapRenderer`, no integration tests against a real GL context. The Mapbox plugin does not render in `flutter_tester`.

### Unit tests (pure Dart, no Flutter)

- **`polygon_validator_test.dart`**
  - Each rule: minimal failing case + minimal passing case.
  - Self-intersection: bowtie (4 vertices), figure-eight (8 vertices), almost-touching (no intersection at epsilon).
  - Inside-boundary: vertex on boundary edge (passes), vertex outside hole (passes — only outer ring vs assignment boundary), vertex outside assignment (fails).
  - Zero-length edge: two coincident vertices (fails); two vertices 1 cm apart (passes).
  - Order-of-failure: a polygon failing rules 1 and 3 → returns rule 1 only (short-circuit).
  - Self-intersection edge index reporting: reports exactly the offending edge pairs, not adjacent neighbors.

- **`feature_geometry_revisions_repository_test.dart`** — Drift in-memory: insert revision + sync_job in one transaction; rollback on simulated failure leaves both untouched.

- **`reshape_mode_controller_test.dart`** — state transitions, undo stack correctness, `selfIntersects` flag updates per drag tick, lock-while-dirty discards.

### Widget tests (`FakeMapRenderer`, `FakeLocationService`, `FakeSyncApi`, `RecordingAnalyticsService`)

- **`map_screen_reshape_test.dart`**
  - Long-press polygon (add-mode off) → action sheet shows three items.
  - Long-press polygon (add-mode on) → no action sheet; long-press consumed by add-mode.
  - Action-sheet `Reshape` → distance-OK path → enters edit mode (banner appears, handles render).
  - Action-sheet `Reshape` → distance-too-far path → override-reason dialog → entered-with-reason; reason persisted into revision row on save.
  - Cancel discards edits; map polygon unchanged.
  - Save with valid edits commits one revision row + one sync_job.
  - Save with invalid edits (each rule) shows rule-specific snackbar; stays in edit mode.
  - Assignment-locked-while-dirty → "Assignment was closed" banner; Exit discards.
  - `Reshape` action item disabled when assignment is locked at long-press time.
  - Reshape on a polygon while a different polygon's `is_new=true` point pin is also on screen → point pin still renders normally; reshape limited to the long-pressed polygon.

- **`reshape_overlay_test.dart`**
  - 4-vertex polygon → 4 vertex handles + 4 midpoint handles render at projected positions.
  - Drag a vertex handle → working ring updates; renderer receives new working geojson.
  - Drag from a midpoint → vertex inserted; second drag-tick moves the inserted vertex.
  - Long-press a vertex → confirm dialog; confirm removes; cancel preserves.
  - Long-press blocked at 3-vertex minimum: dialog opens with confirm **disabled**.
  - Camera change reprojects handle positions; drag continues without flicker.

- **`reshape_banner_test.dart`**
  - "Reshape • 0 edits" → "Reshape • 3 edits" after three ops; Save enabled when dirty.
  - Undo decrements counter and inverts the last op.

### Sync tests

- **`feature_geometry_update_sync_test.dart`** — `FakeSyncApi` records call shape; success → revision marked uploaded + sync_job success; 409 + `geometry_conflict` → revision failed + sync_job dead.

### Analytics tests

- `RecordingAnalyticsService` captures all four events; assert payload shape per scenario (entered, cancelled with ops_made, completed with full op breakdown, validation_failed per rule).

### Manual happy path (final task in plan)

1. Open app, open assignment, open map.
2. Long-press a red polygon → action sheet shows three items.
3. `Reshape` → banner appears; handles render at all corners.
4. Drag a corner; release; banner shows "Reshape • 1 edit"; Save active.
5. Drag a midpoint outward; verify the new vertex stays under the finger; release.
6. Long-press a corner; confirm; vertex disappears.
7. Tap Undo three times; banner returns to "0 edits".
8. Reshape into a bowtie; verify red live edges.
9. Save → snackbar self-intersection error; stay in mode.
10. Fix the polygon; Save → exits to map; polygon shows new shape.
11. Force-quit and relaunch → polygon still has new shape.
12. Go offline; reshape and Save → sync indicator shows pending; back online → uploads cleanly.
13. Repeat the happy path on three real-world test buildings (DoD requirement).

## 10. Analytics

```
map.reshape.entered            { feature_id, vertex_count, override_used: bool }
map.reshape.cancelled          { feature_id, ops_made: int, duration_ms }
map.reshape.completed          { feature_id, vertex_count_before, vertex_count_after,
                                 vertex_moves: int, vertex_adds: int, vertex_removes: int,
                                 override_used: bool, duration_ms }
map.reshape.validation_failed  { feature_id, rule: string, attempt_index: int }
```

All four go through the existing `analyticsServiceProvider`. `NoopAnalyticsService` in production; `ConsoleAnalyticsService` in `kDebugMode`; `RecordingAnalyticsService` in tests.

## 11. AC mapping

| AC story scenario | How it's met |
|---|---|
| **Scenario 1** — move vertex by drag | `ReshapeOverlay` vertex handles are draggable; `ReshapeModeController.moveVertex(ringIdx, vertexIdx, lngLat)` updates the working ring; renderer receives `reshapeWorkingPolygonGeojson` and re-renders the polygon every frame; Save commits. |
| **Scenario 2** — add new vertex via midpoint indicator | Midpoint handles render between every vertex pair; touch-and-drag inserts a new vertex (A2 gesture pattern), entering drag immediately. |
| **Scenario 3** — remove vertex (long-press + confirm; ≥3 enforced) | Long-press handle → `showReshapeRemoveConfirm`. Confirm button is **disabled** when the working ring has 3 vertices. Confirm → `Remove` op pushed to undo stack. |
| **Scenario 4** — validate at save; show error; allow continue | `validateBuildingPolygon` runs all 5 rules at Save; failure → snackbar with rule-specific message; mode stays open. Live red-edge feedback for self-intersection during drag. |
| **Scenario 5** — Cancel reverts | Cancel discards `ReshapeModeController` state; original Drift row never touched; map re-renders from persisted geometry. |
| **Scenario 6** — preserve building metadata | Drift transaction touches only `features.geometry_geojson` and `feature_geometry_revisions`. `submissions`, `building_attributes`, `photos` untouched. |

## 12. Definition-of-done coverage

- **Automated tests:** unit + widget + sync + analytics, covered above.
- **Android:** target platform; iOS not supported by this codebase yet.
- **Sync correctness:** sync tests + manual happy-path step 12.
- **Audit trail:** `feature_geometry_revisions` rows on both client and server, with `edited_by`, `edited_at`, optional `override_reason`.
- **Documentation:** enumerator field guide updated post-merge (separate doc PR; not gated by this story but called out in PR description).
- **QA sign-off on 3 real-world test buildings:** manual happy-path step 13 makes this explicit; PR description carries the checklist.

## 13. Dependencies and migration order

1. Database migration (`011_feature_geometry_updates.sql`) **must ship before** the mobile build that contains this code can be released. No backfill needed (revisions are append-only).
2. Drift schema bump (local DB) ships with the app; `onUpgrade` adds the `FeatureGeometryRevisions` table.
3. No new pub dependencies. All work is pure Dart + existing Mapbox + existing Supabase + existing Drift.

## 14. Open questions deferred to implementation

These are intentionally not specified here — they're judgment calls best made with code in hand:

- Exact handle stroke width / color tokens (matches `RecenterButton` / `ZoomButton` design language).
- Banner exact pixel padding and icon set (uses existing app theme tokens).
- Live red-edge rendering implementation: PolygonAnnotation overlay vs. dedicated `LineLayer`. The first is simpler; the second is more flexible. Implementer's call based on what works cleanly with mapbox_maps_flutter 2.22.
- Whether the live `selfIntersects` recheck runs on every pointer-move event or is throttled to ~30 fps. Validator is fast enough that throttling may be unnecessary; profile during implementation.
