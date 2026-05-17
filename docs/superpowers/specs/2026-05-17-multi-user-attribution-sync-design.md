# Multi-User Attribution Sync — Design

**Date:** 2026-05-17
**Status:** Draft, pending review
**Owner:** @jlescarlan11

## Summary

Today, each FireCheck field worker has an isolated view of an assignment: they download the base map (shapefiles via Drive/FTP), attribute features locally, and upload submissions to Supabase. There is no visibility into what other workers on the same assignment have already done, no conflict detection on overlapping work, and no audit when one worker's data effectively replaces another's via re-upload.

This spec describes a multi-user attribution sync system that:

1. **Shares attributions across users in near-real-time** using Supabase realtime, so workers can see what others have already attributed.
2. **Detects conflicts at upload time** at per-feature granularity, with side-by-side comparison and per-feature "keep mine / keep theirs / skip" decisions.
3. **Treats first upload as the source of truth**, with explicit force-overwrite that is recorded in an audit log.
4. **Flags possible-duplicate new features** added by different users via PostGIS proximity, deferring all dedup decisions to human review.
5. **Never destroys in-progress local work** when other users' edits arrive — local edits are always preserved; cross-user state is shown as badges and resolved only at upload.

The design extends the existing `sync_jobs` push queue, adds two canonical Supabase tables plus an audit log, and introduces a local read-only cache of remote state for badging and the conflict-review UI.

## Goals & Non-Goals

### Goals

- Multiple workers on one assignment can attribute features in parallel without silent data loss.
- A worker can see, on their map, that another worker has already attributed a building or road.
- A worker uploading a conflicting attribution sees the other version side-by-side and picks per feature.
- Force-overwrites are recoverable from audit history.
- New features added by different users that may represent the same physical object are flagged for human review (no auto-merge).
- The system works offline-first; conflicts are detected and resolved when the device is online, never blocking field work.

### Non-Goals

- **Real-time collaborative editing of a single attribution form** (Google-Docs style). Out of scope; attributions are atomic submissions.
- **Automatic merging of attribute values** (e.g., "Alice said 2 floors, Bob said 3, take the average"). All conflicts are user-resolved.
- **Geometry editing of base-map features.** Geometry conflicts only arise for new features; base-map features have a fixed shared FID.
- **Per-field locking** ("Alice is editing the 'roof_material' field"). Lock granularity is the whole submission.
- **Per-user notifications when overwritten.** Audit log only; supervisors review via admin reports.

## Design Decisions

These were settled during brainstorming and are intentionally explicit so future contributors don't relitigate them.

| Decision | Choice | Why |
|---|---|---|
| Scope of multi-user sync | Existing base-map features **and** user-added new features | Full coverage — duplicate-building-in-the-field is a real failure mode. |
| Cross-device sync trigger | **Supabase realtime** + on-reconnect catch-up + on-cold-open full pull | User explicitly chose realtime; the other two paths cover the offline gaps realtime cannot. |
| Existing-feature conflict rule | Server submission exists **and** attribute values differ from mine | Identical values are not conflicts — review time should only be spent on real disagreements. |
| New-feature dedup rule | Same type + centroid within configurable proximity (default 5m) → flag for human review | No automatic merging; always human-in-the-loop. |
| Realtime UX when local edit is in progress | Keep local edit, badge the feature "others have edited this" | Never destroy in-flight work; surface info passively. |
| Overwrite audit | Soft-delete superseded row + full audit history, **no per-user notification** | Recoverable for admins; field workers aren't notified when overwritten. |
| Canonical storage shape | One row per submission with `superseded_at`/`superseded_by_id` (Approach A) | Simplest match for "first upload wins + force-overwrite with audit"; free history; clean realtime story. |

## Architecture Overview

Three layers, mostly reusing existing infrastructure:

### 1. Local (Drift)

The existing `submissions`, `features`, `photos`, and `sync_jobs` tables remain the source of truth for the user's own work. Two thin additions:

- `remote_attributions_cache` — mirrors non-local users' submissions for the current assignment. Populated by realtime + cold-open / reconnect pulls. Clearable on logout. Never blocks local edits.
- `remote_new_features_cache` — same for user-added new features on the current assignment (with WKB geometry for map display).

The existing `submissions` table gains one column: `remoteAttributionId` (set after a successful upload — links the local row to its server canonical row).

### 2. Server (Supabase)

Three new tables:

- `assignment_attributions` — canonical attributions for existing base-map features.
- `assignment_new_features` — canonical user-added new features (with PostGIS geometry + computed centroid).
- `attribution_audit_log` — supersede / force-overwrite / dedup-resolve events.

RLS scopes all access to assignments the user is a member of. Updates only via RPC (no direct client UPDATEs). PostGIS extension required.

### 3. Sync Glue

- **Push:** New `attribution_upload` `sync_jobs` entity type. Job invokes `submit_attribution` RPC; on conflict, job parks in `awaiting_user_resolution` until the user reviews; on resolution, the job calls `resolve_attribution` or marks the local submission `withdrawn`.
- **Pull:** Realtime subscription on the two canonical tables filtered by current `assignment_id`; on reconnect, delta pull by `updated_at > last_sync_at`; on cold-open, full pull.

### Key Invariant

**Never destroy local work.** Realtime arrivals only write to the `remote_*_cache` tables. The user's `submissions` table is only ever modified by the user. UI joins the two for display.

## Data Model

### Supabase

```sql
-- canonical attributions for existing base-map features
create table assignment_attributions (
  id              uuid primary key default gen_random_uuid(),
  assignment_id   uuid not null references assignments(id),
  feature_id      text not null,                  -- shapefile FID, stable across users
  feature_type    text not null,                  -- 'building' | 'road' | ...
  attribute_values jsonb not null,
  photo_refs      jsonb not null default '[]',
  submitted_by    uuid not null references auth.users(id),
  submitted_at    timestamptz not null default now(),
  superseded_at   timestamptz,
  superseded_by_id uuid references assignment_attributions(id),
  -- idempotency key from client: prevents double-insert on retry
  client_submission_id text not null,
  updated_at      timestamptz not null default now(),
  unique (assignment_id, client_submission_id)
);
create index on assignment_attributions (assignment_id, feature_id)
  where superseded_at is null;
create index on assignment_attributions (assignment_id, updated_at);

-- user-added new features
create table assignment_new_features (
  id                  uuid primary key default gen_random_uuid(),
  assignment_id       uuid not null references assignments(id),
  feature_type        text not null,
  geometry            geometry(Geometry, 4326) not null,
  centroid            geography(Point, 4326)
                       generated always as (st_centroid(geometry)::geography) stored,
  attribute_values    jsonb not null,
  photo_refs          jsonb not null default '[]',
  submitted_by        uuid not null references auth.users(id),
  submitted_at        timestamptz not null default now(),
  possible_duplicate_of uuid references assignment_new_features(id),
  dedup_reviewed_at   timestamptz,                  -- null = still pending review
  superseded_at       timestamptz,
  superseded_by_id    uuid references assignment_new_features(id),
  client_submission_id text not null,
  updated_at          timestamptz not null default now(),
  unique (assignment_id, client_submission_id)
);
create index on assignment_new_features using gist (centroid);
create index on assignment_new_features (assignment_id, updated_at);

-- audit trail
create table attribution_audit_log (
  id              uuid primary key default gen_random_uuid(),
  table_name      text not null,            -- 'assignment_attributions' | 'assignment_new_features'
  row_id          uuid not null,
  action          text not null,            -- 'supersede' | 'force_overwrite' | 'dedup_resolve'
  performed_by    uuid not null references auth.users(id),
  performed_at    timestamptz not null default now(),
  prior_snapshot  jsonb not null,           -- full row before the change
  resolution_note text                      -- optional, force-overwrite reason
);
create index on attribution_audit_log (row_id);

-- assignment config (or a column on the existing assignments table)
alter table assignments
  add column dedup_proximity_meters numeric not null default 5;
```

#### RLS

- `select` / `insert` on canonical tables: `auth.uid()` is a member of `assignment_id`.
- `update` / `delete` on canonical tables: denied to clients; only the `submit_attribution`, `resolve_attribution`, and `resolve_new_feature` `security definer` RPCs may modify rows.
- `attribution_audit_log`: insert-only via RPCs; `select` allowed for assignment members so admins/users can view history.

#### Realtime publication

Both `assignment_attributions` and `assignment_new_features` are added to a `multi_user_sync` realtime publication. Clients subscribe with a filter on `assignment_id`.

#### PostGIS proximity trigger

```sql
create or replace function set_possible_duplicate_of()
returns trigger language plpgsql as $$
declare
  threshold numeric;
begin
  select dedup_proximity_meters into threshold
    from assignments where id = NEW.assignment_id;

  select id into NEW.possible_duplicate_of
    from assignment_new_features
    where assignment_id = NEW.assignment_id
      and feature_type = NEW.feature_type
      and superseded_at is null
      and id <> NEW.id
      and st_dwithin(centroid, NEW.centroid, threshold)
    order by st_distance(centroid, NEW.centroid) asc
    limit 1;

  return NEW;
end $$;

create trigger trg_new_feature_dedup
  before insert on assignment_new_features
  for each row execute function set_possible_duplicate_of();
```

### Local (Drift, additions)

```dart
class RemoteAttributionsCache extends Table {
  TextColumn get id => text()();                    // server uuid
  TextColumn get assignmentId => text()();
  TextColumn get featureId => text()();
  TextColumn get featureType => text()();
  TextColumn get attributeValuesJson => text()();
  TextColumn get submittedBy => text()();
  DateTimeColumn get submittedAt => dateTime()();
  DateTimeColumn get supersededAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  @override Set<Column> get primaryKey => {id};
}

class RemoteNewFeaturesCache extends Table {
  TextColumn get id => text()();
  TextColumn get assignmentId => text()();
  TextColumn get featureType => text()();
  BlobColumn get geometryWkb => blob()();
  RealColumn get centroidLat => real()();
  RealColumn get centroidLon => real()();
  TextColumn get attributeValuesJson => text()();
  TextColumn get submittedBy => text()();
  DateTimeColumn get submittedAt => dateTime()();
  TextColumn get possibleDuplicateOf => text().nullable()();
  DateTimeColumn get supersededAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  @override Set<Column> get primaryKey => {id};
}

class AssignmentSyncCursors extends Table {
  TextColumn get assignmentId => text()();
  DateTimeColumn get attributionsLastSyncAt => dateTime().nullable()();
  DateTimeColumn get newFeaturesLastSyncAt => dateTime().nullable()();
  @override Set<Column> get primaryKey => {assignmentId};
}
```

Existing `submissions` table:

```dart
TextColumn get remoteAttributionId => text().nullable()();
// existing 'syncStatus' gains two values: 'awaiting_user_resolution', 'withdrawn'
```

## Sync Flow

### Pull paths

All three feed the same upsert function `cacheUpsertFromServerRows(rows)` so the merge semantics are identical regardless of source.

1. **Cold-open / first time on assignment.** Full pull of non-superseded rows for the assignment. Replaces cache. Sets `attributionsLastSyncAt` / `newFeaturesLastSyncAt` to `max(updated_at)` of the response.
2. **On reconnect.** Delta pull `where updated_at > last_sync_at` (includes superseded rows so badges disappear correctly). Upsert by id. Advance cursor to `max(updated_at)` of result set, *not* `now()` — avoids gaps from server clock drift / replication lag.
3. **Realtime while online.** Supabase realtime subscription on both tables filtered by `assignment_id`. Each event upserts one row. Same code path as the reconnect delta.

### Connection state machine

```
offline → reconnecting → online (realtime live) → backgrounded (realtime paused) → offline
```

- `offline → reconnecting`: triggered by network restoration.
- `reconnecting → online`: triggered by successful delta pull. Subscription opened after delta completes (otherwise realtime events could land before the cache catches up).
- `online → backgrounded`: app moves to background. After N minutes (default 2), drop the subscription to save battery.
- `backgrounded → offline`: backgrounded with no network; transition to offline state.
- Any → offline: subscription closed; pending events recovered on next reconnect via cursor.

### Push path

A new `sync_jobs.entity_type = 'attribution_upload'`. The job:

1. Calls RPC `submit_attribution(local_submission_id, feature_id, attribute_values, photo_refs, base_version_id?)`.
2. If response is `committed` or `agreed_skip`: write `remoteAttributionId` to the local submission row, mark job complete.
3. If response includes `conflicts` or `dedup_pending`: mark local submission `awaiting_user_resolution`, mark job parked. UI surfaces the review prompt.
4. After user resolves: spawn `resolve_attribution` or `resolve_new_feature` RPC call (as part of the same parked job or a follow-on job).

The job inherits all existing retry/backoff behavior. RPCs are idempotent on `client_submission_id` (the local submission UUID); retries return the same response.

## Conflict Detection & Upload Flow

### `submit_attribution` RPC

```
submit_attribution(
  client_submission_id: uuid,
  feature_id: text,
  feature_type: text,
  attribute_values: jsonb,
  photo_refs: jsonb,
  base_version_id: uuid?           -- the server row the user knew about, if any
) returns SubmitResult
```

Pseudocode:

```
begin transaction
  -- idempotency
  if exists (row with this client_submission_id):
    return existing result snapshot

  current := select latest non-superseded row for (assignment_id, feature_id)

  if current is null:
    insert new row, status 'committed'
    return { status: 'committed', id: new.id }

  if current.id == base_version_id:
    -- user explicitly knew about and overrode this version
    supersede current, insert new row, audit 'supersede'
    return { status: 'committed', id: new.id }

  if current.attribute_values == attribute_values:
    -- agreement, not a conflict
    return { status: 'agreed_skip', id: current.id }

  -- real conflict
  insert new row, status 'pending_resolution'
  return { status: 'conflict',
           pending_id: new.id,
           their_row: current }
commit
```

The supersede UPDATE is conditional on `superseded_at IS NULL` (optimistic lock). If a concurrent transaction has already superseded `current`, the UPDATE affects 0 rows; this transaction re-reads `current` and either becomes an agreed_skip, commits cleanly, or returns a fresh conflict.

For new features, the parallel RPC `submit_new_feature` inserts into `assignment_new_features`:

```
submit_new_feature(
  client_submission_id: uuid,
  feature_type: text,
  geometry: geometry,
  attribute_values: jsonb,
  photo_refs: jsonb
) returns SubmitNewFeatureResult
```

The proximity trigger populates `possible_duplicate_of` on insert. If non-null, the RPC returns `{ status: 'dedup_pending', pending_id, possible_duplicate_of_row }`; otherwise `{ status: 'committed', id }`. The pending row is inserted either way — review only clears `dedup_reviewed_at` or supersedes one of the two rows. Idempotency on `client_submission_id` matches `submit_attribution`.

### `resolve_attribution` RPC

```
resolve_attribution(pending_id: uuid, decision: 'keep_theirs' | 'force_overwrite')
```

- `keep_theirs`: delete the pending row (no audit — nothing changed canonically). Server returns the current canonical row so the client can update its cache and mark its local submission withdrawn.
- `force_overwrite`: supersede the prior canonical row, promote the pending row to canonical, insert audit log entry (`action='force_overwrite'`).

### `resolve_new_feature` RPC

```
resolve_new_feature(pending_id: uuid, decision: 'keep_both' | 'replace_theirs' | 'discard_mine')
```

- `keep_both`: set `dedup_reviewed_at = now()` on the pending row; both rows coexist as separate features.
- `replace_theirs`: supersede `possible_duplicate_of`, set `dedup_reviewed_at`, audit `dedup_resolve`.
- `discard_mine`: soft-delete the pending row (`superseded_at = now()`, `superseded_by_id = null`), audit.

### Photo handling

Photos are uploaded to Supabase Storage *before* the attribution RPC is called (existing flow). Consequences:

- `committed` / `force_overwrite`: photos are referenced by the new canonical row — kept.
- `agreed_skip`: photos are already uploaded but the existing canonical row stays in place — Bob's photos become orphans pointing at the same content the existing row already represents. Cleanup job will remove them.
- `keep_theirs` / `discard_mine`: Bob's photos are orphans — cleanup job removes them.

A scheduled storage-cleanup job that deletes storage objects with no references is out of scope for this spec — separate ticket.

## UX

### Map screen badge

A feature shows a "👥 others edited" badge when:

- There exists a non-superseded row in `remote_attributions_cache` for that feature authored by a different user, AND
- (The current user has no local submission for it) OR (the local submission's `attribute_values != remote row's attribute_values`).

Tapping a badged feature opens a mini-card with:
- Author name
- Submitted time (relative)
- "View their answers" button → opens a read-only attribute view.

When the user has a local submission, the card also shows "Compare with mine" → side-by-side view (same UI as upload-time conflict review, but no decision buttons; just informational).

### Upload review screen

After tapping Upload, the app sends the batch and receives:

```
{
  committed:        [submission_id, …],
  agreed_skipped:   [submission_id, …],
  conflicts:        [ { pending_id, feature_id, my_values, their_values, their_author, their_time } ],
  dedup_pending:    [ { pending_id, geometry, possible_duplicate_of, their_values, their_author } ]
}
```

If `conflicts` and `dedup_pending` are both empty, upload completes silently. Otherwise the review screen opens — a single list of items needing decisions:

- **Conflict items** show feature id, feature type, and "X of Y fields differ". Tap → side-by-side compare.
- **Dedup items** show a mini-map with both geometries and feature type. Tap → side-by-side compare.

#### Side-by-side compare (existing-feature conflict)

```
┌────────────────────────────────────────────────────┐
│  Building #FID-4218                                │
│                                                    │
│  ┌── Yours ────────┐  ┌── Theirs ─────────────┐    │
│  │ roof: tile      │  │ roof: tile             │    │
│  │ floors: 3       │  │ floors: 2  ◀── differs│    │
│  │ use: residential│  │ use: residential       │    │
│  └─────────────────┘  └────────────────────────┘    │
│                                                    │
│  Theirs by Alice • 2026-05-15 14:22                │
│                                                    │
│  [ Hide identical fields ]                         │
│                                                    │
│  [ Keep theirs ]  [ Use mine ]  [ Skip — later ]   │
└────────────────────────────────────────────────────┘
```

- **Keep theirs** (primary, large button, default focus).
- **Use mine** (secondary, slightly muted).
- **Skip — decide later** (tertiary, text button). Leaves the pending row in place; local submission stays `awaiting_user_resolution`.

A toggle "Hide identical fields" defaults to ON when ≥5 fields are identical — keeps cognitive load down on long forms.

A "Decide all remaining" shortcut at the bottom is **disabled until the user has reviewed at least one item individually**, to prevent reflexive bulk-overwriting.

#### Side-by-side compare (new-feature dedup)

Same layout, but with:
- Mini-map at top showing both geometries.
- Distance between centroids.
- Buttons: `[ Keep both ]` `[ Replace theirs ]` `[ Discard mine ]`.

## Error Handling & Edge Cases

- **Network failure mid-RPC.** RPC is idempotent on `client_submission_id`. The retry returns the same response (committed → committed, conflict → same conflict). Sync job retries seamlessly.
- **Two users force-overwrite each other in quick succession.** Optimistic lock on `superseded_at IS NULL`. The loser's RPC sees a fresh canonical row and returns a new conflict; user re-reviews. Audit log captures both events.
- **User resolves a conflict offline.** Resolution is queued as a sync job (`attribution_resolve` entity type, or as a continuation of the parked `attribution_upload` job). Retried when online.
- **Assignment membership revoked.** Realtime delivery filters by RLS; revoked user stops receiving events. On next foreground, an attempted full-pull returns no rows; cache for that assignment is purged.
- **Clock skew.** Server timestamps only. Client `submitted_at` is informational. Ordering uses server columns.
- **Photo upload partially fails.** Submission stays in `queued`/`uploading_photos`; canonical row is not inserted until all photos succeed. Conflict check runs only at attribution insert time.
- **Soft-deleted rows reappearing on the map.** Realtime emits an UPDATE event when `superseded_at` is set. Clients unbadge accordingly.
- **Stale `base_version_id`.** If the user saw version V1, then V1 was superseded by Alice's V2, then user uploads with `base_version_id=V1`: server detects V1 is superseded, treats this as a real conflict (their `base_version_id` does not match `current.id`).
- **Cache divergence after crash.** On suspect cache age (e.g., last sync > 24h) or detected gap, force a full pull rather than a delta.
- **Realtime backpressure.** If realtime drops events under load, the next reconnect's delta pull catches up.

## Testing

### Unit

- Conflict rule: differ vs. identical attribute values.
- Proximity trigger: same type within threshold → flagged; different type → not flagged; outside threshold → not flagged.
- Supersede transaction: optimistic lock contention; loser re-runs cleanly.
- Cursor advancement: max(updated_at) of response, not now().

### Repository / integration (local)

- `remote_attributions_cache` upsert and supersede roundtrip.
- Realtime event → cache row materialization.
- Connection state transitions (offline ↔ online ↔ background) drive correct pull/subscription behavior.

### Integration (server)

- Two Supabase auth sessions submit to same feature; second receives conflict; resolves with `force_overwrite`; audit row exists with prior snapshot.
- Two sessions submit nearby new features; second receives `dedup_pending`; resolves with `keep_both`; both rows have `dedup_reviewed_at` set.
- Idempotent RPC: same `client_submission_id` returns identical response on retry.

### End-to-end (manual on device)

- Field worker A offline-attributes 5 buildings; B online-attributes the same 5 buildings; A reconnects and uploads; sees 5 conflicts; resolves mixed (keep theirs / use mine / skip).
- B receives realtime events as A resolves with `force_overwrite`; B's map badges update.

### Performance

- Realtime throughput: 100 features × 5 active users churning attributions for 10 minutes. Cache writes batched per 250ms; UI not blocked.
- Cold-open pull on assignment with 5k attributions completes under 3s on 4G.

## Open Questions / Deferred Work

- **Photo orphan cleanup** — separate ticket. Out of scope here.
- **Admin "view audit history" UI** — the table is in place; the screen to browse it is a follow-up.
- **Bulk supervisor "force resolve N conflicts for worker X"** — out of scope; manual per-feature only for V1.
- **Geometry conflict for base-map features** — out of scope (base-map features are not user-editable in geometry).
- **Per-assignment proximity threshold tuning UI** — for now a DB-level config on `assignments`. Editing UI follows later.

## Migration Plan (high level)

1. **Backend (no client change):** Create new tables, RLS, trigger, RPCs. Enable realtime publication. Existing client unaffected.
2. **Client cache + pull:** Add Drift tables; implement cold-open + reconnect pull. UI still ignores cache — no badges yet.
3. **Client realtime subscription:** Add subscription with state machine. Still no UI.
4. **Map badge UI:** Render badges from cache. Read-only at this stage.
5. **Push migration:** Switch `submission` uploads from existing path to `attribution_upload` job via the new RPC. Fallback path retained for one release.
6. **Conflict review UI:** Ship the review screen and resolution RPCs.
7. **New-feature dedup UI:** Ship dedup review.
8. **Decommission old upload path.**

Each step is independently shippable; conflicts only become visible to users at step 4 (badges) and actionable at step 6 (review screen).
