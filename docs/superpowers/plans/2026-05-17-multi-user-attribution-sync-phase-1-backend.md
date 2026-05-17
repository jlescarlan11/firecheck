# Multi-User Attribution Sync — Phase 1: Backend Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land all server-side infrastructure for multi-user attribution sync — multi-membership, supersede columns, PostGIS dedup, audit log, conflict-aware RPCs, and realtime publication — without changing any client code.

**Architecture:** Eleven sequential Supabase migrations (`015` → `025`). Existing `submissions` and `features` tables are extended with conflict-tracking columns; a new `assignment_members` table generalizes the single-enumerator RLS; new RPCs `submit_attribution_with_conflict_check`, `submit_new_feature_with_dedup_check`, `resolve_attribution`, `resolve_new_feature` wrap the existing upload bundle pattern with conflict semantics. Each migration ships with verification SQL that the engineer runs against the target Supabase database.

**Tech Stack:** PostgreSQL 15 (Supabase), PostGIS, PL/pgSQL, Supabase realtime publications, `psql` (or Supabase CLI) for apply + verify.

**Reference spec:** `docs/superpowers/specs/2026-05-17-multi-user-attribution-sync-design.md` (with **Appendix A** governing schema decisions).

**Migrations directory:** `supabase/migrations/`. Existing latest is `014_download_events.sql`; this plan adds `015` through `025`.

**How to apply each migration during development:**

Migrations are SQL files; the project does not have `supabase/config.toml` (no local stack). The engineer applies each file against a Supabase dev or staging database using one of:

```bash
# Option A — psql with direct connection string (recommended for verification iteration)
export SUPABASE_DB_URL='postgresql://postgres:<pwd>@<host>:5432/postgres'
psql "$SUPABASE_DB_URL" -f supabase/migrations/<file>.sql

# Option B — Supabase CLI against a linked project
supabase db push
```

All verification queries below are runnable as `psql "$SUPABASE_DB_URL" -c "<query>"`.

---

## File Structure

All changes in this phase are SQL migrations. No Dart, no client-side code.

```
supabase/migrations/
  015_assignment_members.sql           # Task 1 — join table + backfill from assignments.enumerator_id
  016_rls_via_membership.sql           # Task 2 — refactor RLS on 7 tables to use assignment_members
  017_submissions_supersede.sql        # Task 3 — superseded_at / superseded_by_id on submissions
  018_features_dedup_columns.sql       # Task 4 — possible_duplicate_of, dedup_reviewed_at, centroid on features
  019_features_proximity_trigger.sql   # Task 5 — trigger populating possible_duplicate_of on insert
  020_attribution_audit_log.sql        # Task 6 — new audit table
  021_attribution_values_equal_fn.sql  # Task 7 — helper function comparing typed-child rows
  022_submit_attribution_conflict.sql  # Task 8 — conflict-aware submission RPC
  023_submit_new_feature_dedup.sql     # Task 9 — dedup-aware new-feature RPC
  024_resolve_rpcs.sql                 # Task 10 — resolve_attribution + resolve_new_feature RPCs
  025_realtime_publication.sql         # Task 11 — add submissions + features to supabase_realtime publication
```

Each migration is self-contained, idempotent where reasonable (uses `create … if not exists`, `drop policy if exists` before `create policy`), and ships with verification SQL.

---

## Task 1: `assignment_members` join table + backfill

Generalizes the single-owner assignment model into many-to-many. Backfills one row per existing assignment from `assignments.enumerator_id` so existing functionality keeps working unchanged.

**Files:**
- Create: `supabase/migrations/015_assignment_members.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/015_assignment_members.sql
-- Generalizes the single-owner assignment model. Existing
-- assignments.enumerator_id is retained as the "creator" but
-- RLS will be driven by membership rows after migration 016.

create table public.assignment_members (
  assignment_id uuid not null references public.assignments(id) on delete cascade,
  enumerator_id uuid not null references public.enumerators(id) on delete cascade,
  role          text not null default 'member', -- 'owner' | 'member'
  joined_at     timestamptz not null default now(),
  primary key (assignment_id, enumerator_id)
);

create index assignment_members_by_enumerator
  on public.assignment_members (enumerator_id);

-- Backfill: every existing assignment becomes a single-member assignment
-- with the existing enumerator as 'owner'.
insert into public.assignment_members (assignment_id, enumerator_id, role)
select id, enumerator_id, 'owner'
from public.assignments
on conflict do nothing;

alter table public.assignment_members enable row level security;

-- Members can see their own membership rows (used by client to list assignments).
create policy assignment_members_self_read
  on public.assignment_members
  for select
  using (enumerator_id = auth.uid());

-- For now, INSERT/DELETE on this table are admin-only (no client policy).
-- A future Phase will add owner-managed invites.
```

- [ ] **Step 2: Apply the migration**

```bash
psql "$SUPABASE_DB_URL" -f supabase/migrations/015_assignment_members.sql
```
Expected: `CREATE TABLE`, `CREATE INDEX`, `INSERT 0 N`, `ALTER TABLE`, `CREATE POLICY` (no errors).

- [ ] **Step 3: Verify table + backfill counts match**

```bash
psql "$SUPABASE_DB_URL" -c "
  select
    (select count(*) from public.assignments) as assignments_count,
    (select count(*) from public.assignment_members) as members_count,
    (select count(*) from public.assignment_members where role = 'owner') as owners_count;
"
```
Expected: `assignments_count == members_count == owners_count` (every existing assignment got exactly one owner row).

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/015_assignment_members.sql
git commit -m "feat(db): add assignment_members for multi-user assignments"
```

---

## Task 2: RLS refactor — all assignment-scoped tables use membership

Replaces direct `enumerator_id = auth.uid()` checks with membership lookups. Touches 7 tables. The migration drops the old policies and replaces them in a single transaction so there is no window of unprotected access.

**Files:**
- Create: `supabase/migrations/016_rls_via_membership.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/016_rls_via_membership.sql
-- Replaces single-owner RLS checks with assignment_members lookups.
-- Touched tables: assignments, features, submissions, building_attributes,
-- road_attributes, household_surveys, photos.

begin;

-- assignments: a user can see/upsert an assignment if they're a member.
drop policy if exists assignments_own_rw on public.assignments;
create policy assignments_member_rw on public.assignments
  for all
  using (
    exists (
      select 1 from public.assignment_members am
      where am.assignment_id = assignments.id
        and am.enumerator_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.assignment_members am
      where am.assignment_id = assignments.id
        and am.enumerator_id = auth.uid()
    )
  );

-- features: scoped by parent assignment membership.
drop policy if exists features_via_assignment_rw on public.features;
create policy features_via_membership_rw on public.features
  for all
  using (
    exists (
      select 1 from public.assignment_members am
      where am.assignment_id = features.assignment_id
        and am.enumerator_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.assignment_members am
      where am.assignment_id = features.assignment_id
        and am.enumerator_id = auth.uid()
    )
  );

-- submissions: scoped via features → assignment_members.
drop policy if exists submissions_via_feature_rw on public.submissions;
create policy submissions_via_membership_rw on public.submissions
  for all
  using (
    exists (
      select 1 from public.features f
      join public.assignment_members am on am.assignment_id = f.assignment_id
      where f.id = submissions.feature_id
        and am.enumerator_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.features f
      join public.assignment_members am on am.assignment_id = f.assignment_id
      where f.id = submissions.feature_id
        and am.enumerator_id = auth.uid()
    )
  );

-- building_attributes, road_attributes, household_surveys: scoped via submission → feature → membership.
drop policy if exists building_attrs_via_submission_rw on public.building_attributes;
create policy building_attrs_via_membership_rw on public.building_attributes
  for all
  using (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignment_members am on am.assignment_id = f.assignment_id
      where s.id = building_attributes.submission_id
        and am.enumerator_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignment_members am on am.assignment_id = f.assignment_id
      where s.id = building_attributes.submission_id
        and am.enumerator_id = auth.uid()
    )
  );

drop policy if exists road_attrs_via_submission_rw on public.road_attributes;
create policy road_attrs_via_membership_rw on public.road_attributes
  for all
  using (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignment_members am on am.assignment_id = f.assignment_id
      where s.id = road_attributes.submission_id
        and am.enumerator_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignment_members am on am.assignment_id = f.assignment_id
      where s.id = road_attributes.submission_id
        and am.enumerator_id = auth.uid()
    )
  );

drop policy if exists household_via_submission_rw on public.household_surveys;
create policy household_via_membership_rw on public.household_surveys
  for all
  using (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignment_members am on am.assignment_id = f.assignment_id
      where s.id = household_surveys.submission_id
        and am.enumerator_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignment_members am on am.assignment_id = f.assignment_id
      where s.id = household_surveys.submission_id
        and am.enumerator_id = auth.uid()
    )
  );

-- photos: scoped via submission → feature → membership.
drop policy if exists photos_via_submission_rw on public.photos;
create policy photos_via_membership_rw on public.photos
  for all
  using (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignment_members am on am.assignment_id = f.assignment_id
      where s.id = photos.submission_id
        and am.enumerator_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignment_members am on am.assignment_id = f.assignment_id
      where s.id = photos.submission_id
        and am.enumerator_id = auth.uid()
    )
  );

commit;
```

- [ ] **Step 2: Apply the migration**

```bash
psql "$SUPABASE_DB_URL" -f supabase/migrations/016_rls_via_membership.sql
```
Expected: `BEGIN`, multiple `DROP POLICY`/`CREATE POLICY`, `COMMIT`.

- [ ] **Step 3: Verify policy names changed**

```bash
psql "$SUPABASE_DB_URL" -c "
  select schemaname, tablename, policyname
  from pg_policies
  where schemaname = 'public'
    and tablename in (
      'assignments','features','submissions','building_attributes',
      'road_attributes','household_surveys','photos'
    )
  order by tablename, policyname;
"
```
Expected: each of the 7 tables has exactly one policy whose name ends in `_via_membership_rw` (or `_member_rw` for `assignments`). No `_via_submission_rw` / `_via_feature_rw` / `_own_rw` remain.

- [ ] **Step 4: Behavior check — non-member is blocked**

Pick an existing enumerator id and an assignment they do NOT own. Substitute placeholders below.

```bash
psql "$SUPABASE_DB_URL" -c "
  set local role authenticated;
  set local request.jwt.claim.sub = '<OTHER_ENUMERATOR_UUID>';
  select count(*) from public.assignments where id = '<ASSIGNMENT_UUID>';
"
```
Expected: `0` rows visible (RLS blocks non-member).

Then add membership and re-check:

```bash
psql "$SUPABASE_DB_URL" -c "
  insert into public.assignment_members (assignment_id, enumerator_id, role)
    values ('<ASSIGNMENT_UUID>', '<OTHER_ENUMERATOR_UUID>', 'member');
  set local role authenticated;
  set local request.jwt.claim.sub = '<OTHER_ENUMERATOR_UUID>';
  select count(*) from public.assignments where id = '<ASSIGNMENT_UUID>';
"
```
Expected: `1` row visible. (Roll back the test insert afterwards: `delete from public.assignment_members where assignment_id = '<ASSIGNMENT_UUID>' and enumerator_id = '<OTHER_ENUMERATOR_UUID>';`)

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/016_rls_via_membership.sql
git commit -m "feat(db): RLS via assignment_members on all assignment-scoped tables"
```

---

## Task 3: Supersede columns on `submissions`

Adds the two columns that drive first-upload-wins + force-overwrite audit. Includes a partial index for fast "current submission for this feature" lookups.

**Files:**
- Create: `supabase/migrations/017_submissions_supersede.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/017_submissions_supersede.sql
-- Adds the supersede columns that drive the conflict / force-overwrite model.
-- A non-superseded submission for a (feature_id) is the canonical attribution.

alter table public.submissions
  add column if not exists superseded_at timestamptz,
  add column if not exists superseded_by_id uuid references public.submissions(id) on delete set null;

-- Fast "current attribution for this feature" lookup.
create index if not exists submissions_current_by_feature
  on public.submissions (feature_id)
  where superseded_at is null;

-- Optimistic-lock support: indexes the pair so concurrent supersede races
-- can use cheap WHERE clauses.
create index if not exists submissions_supersede_pair
  on public.submissions (id, superseded_at);
```

- [ ] **Step 2: Apply the migration**

```bash
psql "$SUPABASE_DB_URL" -f supabase/migrations/017_submissions_supersede.sql
```
Expected: `ALTER TABLE`, `CREATE INDEX`, `CREATE INDEX`.

- [ ] **Step 3: Verify columns and indexes exist**

```bash
psql "$SUPABASE_DB_URL" -c "
  select column_name, data_type, is_nullable
  from information_schema.columns
  where table_schema='public' and table_name='submissions'
    and column_name in ('superseded_at','superseded_by_id');
"
```
Expected: 2 rows, both nullable.

```bash
psql "$SUPABASE_DB_URL" -c "
  select indexname from pg_indexes
  where schemaname='public' and tablename='submissions'
    and indexname in ('submissions_current_by_feature','submissions_supersede_pair');
"
```
Expected: 2 rows.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/017_submissions_supersede.sql
git commit -m "feat(db): add supersede columns + indexes to submissions"
```

---

## Task 4: Dedup columns + computed centroid on `features`

Adds the columns the new-feature dedup workflow needs and the generated centroid that the proximity index will live on. `centroid` is stored generated so PostGIS can index it directly.

**Files:**
- Create: `supabase/migrations/018_features_dedup_columns.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/018_features_dedup_columns.sql
-- Adds dedup columns to features. Only meaningful when is_new = true.
-- centroid is a stored generated column so it can be GIST-indexed.

alter table public.features
  add column if not exists possible_duplicate_of uuid
    references public.features(id) on delete set null,
  add column if not exists dedup_reviewed_at timestamptz;

-- Generated centroid column for proximity queries.
-- Cast to geography so distances are meters, not degrees.
alter table public.features
  add column if not exists centroid geography(Point, 4326)
    generated always as (st_centroid(geometry::geometry)::geography) stored;

-- GIST index used by the proximity trigger (Task 5).
create index if not exists features_centroid_gist
  on public.features using gist (centroid);

-- Per-assignment dedup config — default 5m, override per assignment if needed.
alter table public.assignments
  add column if not exists dedup_proximity_meters numeric not null default 5;
```

- [ ] **Step 2: Apply the migration**

```bash
psql "$SUPABASE_DB_URL" -f supabase/migrations/018_features_dedup_columns.sql
```
Expected: `ALTER TABLE` × 3, `CREATE INDEX`.

- [ ] **Step 3: Verify centroid is populated for existing rows**

```bash
psql "$SUPABASE_DB_URL" -c "
  select count(*) as total,
         count(centroid) as with_centroid
  from public.features;
"
```
Expected: `total == with_centroid` (generated columns are populated on add).

- [ ] **Step 4: Verify new columns exist**

```bash
psql "$SUPABASE_DB_URL" -c "
  select column_name from information_schema.columns
  where table_schema='public' and table_name='features'
    and column_name in ('possible_duplicate_of','dedup_reviewed_at','centroid');
"
```
Expected: 3 rows.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/018_features_dedup_columns.sql
git commit -m "feat(db): add dedup columns + centroid to features"
```

---

## Task 5: Proximity trigger on `features`

Populates `possible_duplicate_of` on insert of a new feature (`is_new = true`) when another non-superseded same-type feature exists within `assignments.dedup_proximity_meters`. Does nothing for base-map features.

**Files:**
- Create: `supabase/migrations/019_features_proximity_trigger.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/019_features_proximity_trigger.sql
-- Sets features.possible_duplicate_of for newly-added user features
-- when a same-type feature already exists within the assignment's
-- dedup_proximity_meters. No-op for is_new = false (base map) rows.

create or replace function public.set_feature_possible_duplicate()
returns trigger
language plpgsql
as $$
declare
  v_threshold numeric;
begin
  if NEW.is_new is not true then
    return NEW;
  end if;

  select dedup_proximity_meters into v_threshold
  from public.assignments
  where id = NEW.assignment_id;

  if v_threshold is null then
    v_threshold := 5;
  end if;

  select id into NEW.possible_duplicate_of
  from public.features f
  where f.assignment_id = NEW.assignment_id
    and f.feature_type = NEW.feature_type
    and f.is_new = true
    and f.id <> NEW.id
    and not exists (
      -- Skip features whose latest submission is superseded with no replacement
      -- (i.e., the feature was "discarded mine" during a prior dedup resolve).
      select 1 from public.submissions s
      where s.feature_id = f.id
        and s.superseded_at is not null
        and s.superseded_by_id is null
    )
    and st_dwithin(f.centroid, NEW.centroid, v_threshold)
  order by st_distance(f.centroid, NEW.centroid) asc
  limit 1;

  return NEW;
end;
$$;

drop trigger if exists trg_features_dedup on public.features;
create trigger trg_features_dedup
  before insert on public.features
  for each row
  execute function public.set_feature_possible_duplicate();
```

- [ ] **Step 2: Apply the migration**

```bash
psql "$SUPABASE_DB_URL" -f supabase/migrations/019_features_proximity_trigger.sql
```
Expected: `CREATE FUNCTION`, `DROP TRIGGER`, `CREATE TRIGGER`.

- [ ] **Step 3: Test the trigger end-to-end**

Pick a real `assignment_id` you have write access to via the dev role (or run as superuser via psql for the test).

```bash
psql "$SUPABASE_DB_URL" <<'EOF'
do $$
declare
  v_aid uuid := '<TEST_ASSIGNMENT_UUID>';
  v_f1 uuid := gen_random_uuid();
  v_f2 uuid := gen_random_uuid();
  v_f3 uuid := gen_random_uuid();
begin
  -- 1m apart - within 5m threshold
  insert into public.features (id, assignment_id, feature_type, geometry, is_new)
    values
      (v_f1, v_aid, 'building',
        st_geographyfromtext('POINT(120.9842 14.5995)')::geometry,
        true);
  insert into public.features (id, assignment_id, feature_type, geometry, is_new)
    values
      (v_f2, v_aid, 'building',
        st_geographyfromtext('POINT(120.98421 14.5995)')::geometry, -- ~1m east
        true);
  -- 50m apart - well outside threshold
  insert into public.features (id, assignment_id, feature_type, geometry, is_new)
    values
      (v_f3, v_aid, 'building',
        st_geographyfromtext('POINT(120.98470 14.5995)')::geometry, -- ~50m east of f1
        true);

  raise notice 'f1.possible_duplicate_of: %', (select possible_duplicate_of from public.features where id = v_f1);
  raise notice 'f2.possible_duplicate_of: %', (select possible_duplicate_of from public.features where id = v_f2);
  raise notice 'f3.possible_duplicate_of: %', (select possible_duplicate_of from public.features where id = v_f3);

  -- Cleanup
  delete from public.features where id in (v_f1, v_f2, v_f3);
end $$;
EOF
```
Expected NOTICEs:
- `f1.possible_duplicate_of: <null>` (first to land — no prior)
- `f2.possible_duplicate_of: <v_f1>` (within 5m of f1)
- `f3.possible_duplicate_of: <null>` (50m away — outside threshold)

- [ ] **Step 4: Test the trigger ignores `is_new=false`**

```bash
psql "$SUPABASE_DB_URL" <<'EOF'
do $$
declare
  v_aid uuid := '<TEST_ASSIGNMENT_UUID>';
  v_f1 uuid := gen_random_uuid();
  v_f2 uuid := gen_random_uuid();
begin
  insert into public.features (id, assignment_id, feature_type, geometry, is_new)
    values (v_f1, v_aid, 'building',
            st_geographyfromtext('POINT(120.9842 14.5995)')::geometry, false);
  insert into public.features (id, assignment_id, feature_type, geometry, is_new)
    values (v_f2, v_aid, 'building',
            st_geographyfromtext('POINT(120.98421 14.5995)')::geometry, false);

  raise notice 'f2.possible_duplicate_of (base-map): %',
    (select possible_duplicate_of from public.features where id = v_f2);

  delete from public.features where id in (v_f1, v_f2);
end $$;
EOF
```
Expected: `f2.possible_duplicate_of (base-map): <null>` (trigger short-circuits on `is_new = false`).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/019_features_proximity_trigger.sql
git commit -m "feat(db): proximity trigger for new-feature dedup"
```

---

## Task 6: `attribution_audit_log` table

Captures every supersede / force-overwrite / dedup-resolve event with the prior row snapshot. Insert-only from RPCs; readable by assignment members.

**Files:**
- Create: `supabase/migrations/020_attribution_audit_log.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/020_attribution_audit_log.sql
-- Records every supersede / force-overwrite / dedup-resolve event with the
-- pre-change row snapshot. Insert-only via RPCs. Readable by assignment members.

create table public.attribution_audit_log (
  id              uuid primary key default gen_random_uuid(),
  table_name      text not null check (table_name in ('submissions','features')),
  row_id          uuid not null,
  action          text not null check (action in ('supersede','force_overwrite','dedup_resolve')),
  performed_by    uuid not null references public.enumerators(id) on delete set null,
  performed_at    timestamptz not null default now(),
  prior_snapshot  jsonb not null,
  resolution_note text
);

create index attribution_audit_log_by_row
  on public.attribution_audit_log (row_id);

create index attribution_audit_log_by_actor
  on public.attribution_audit_log (performed_by, performed_at desc);

alter table public.attribution_audit_log enable row level security;

-- Members of the assignment that the audited row belongs to may select.
-- (table_name disambiguates the parent join.)
create policy audit_log_via_membership_read on public.attribution_audit_log
  for select
  using (
    case table_name
      when 'submissions' then
        exists (
          select 1 from public.submissions s
          join public.features f on f.id = s.feature_id
          join public.assignment_members am on am.assignment_id = f.assignment_id
          where s.id = attribution_audit_log.row_id
            and am.enumerator_id = auth.uid()
        )
      when 'features' then
        exists (
          select 1 from public.features f
          join public.assignment_members am on am.assignment_id = f.assignment_id
          where f.id = attribution_audit_log.row_id
            and am.enumerator_id = auth.uid()
        )
      else false
    end
  );

-- INSERTs come only from security-definer RPCs (no client policy).
```

- [ ] **Step 2: Apply the migration**

```bash
psql "$SUPABASE_DB_URL" -f supabase/migrations/020_attribution_audit_log.sql
```
Expected: `CREATE TABLE`, `CREATE INDEX` × 2, `ALTER TABLE`, `CREATE POLICY`.

- [ ] **Step 3: Verify table + policy exist**

```bash
psql "$SUPABASE_DB_URL" -c "
  select tablename, policyname from pg_policies
  where schemaname='public' and tablename='attribution_audit_log';
"
```
Expected: one row, `policyname = audit_log_via_membership_read`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/020_attribution_audit_log.sql
git commit -m "feat(db): attribution_audit_log table with membership-scoped read RLS"
```

---

## Task 7: `attribution_values_equal` helper function

Compares two `submissions` rows by their typed child-table values (`building_attributes` / `road_attributes` / `household_surveys`). Used by the conflict-check RPC to decide whether two attributions agree.

**Files:**
- Create: `supabase/migrations/021_attribution_values_equal_fn.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/021_attribution_values_equal_fn.sql
-- Returns true when two submissions carry semantically identical
-- attribute values (same does_not_exist, same typed child row).
-- Used by submit_attribution_with_conflict_check to detect agreements.

create or replace function public.attribution_values_equal(
  a_submission_id uuid,
  b_submission_id uuid,
  v_feature_type text
)
returns boolean
language plpgsql
stable
as $$
declare
  a_dne boolean;  b_dne boolean;
  a_remarks text; b_remarks text;
  a_jsonb jsonb;  b_jsonb jsonb;
begin
  select does_not_exist, remarks into a_dne, a_remarks
    from public.submissions where id = a_submission_id;
  select does_not_exist, remarks into b_dne, b_remarks
    from public.submissions where id = b_submission_id;

  -- "Does not exist" is a top-level attribution — must agree on its own.
  if coalesce(a_dne, false) <> coalesce(b_dne, false) then
    return false;
  end if;

  -- If either is "does not exist", child values are irrelevant.
  if coalesce(a_dne, false) = true then
    return true;
  end if;

  -- Compare typed child rows by feature type.
  case v_feature_type
    when 'building' then
      select to_jsonb(ba.*) - 'submission_id' into a_jsonb
        from public.building_attributes ba where ba.submission_id = a_submission_id;
      select to_jsonb(ba.*) - 'submission_id' into b_jsonb
        from public.building_attributes ba where ba.submission_id = b_submission_id;
    when 'road' then
      select to_jsonb(ra.*) - 'submission_id' into a_jsonb
        from public.road_attributes ra where ra.submission_id = a_submission_id;
      select to_jsonb(ra.*) - 'submission_id' into b_jsonb
        from public.road_attributes ra where ra.submission_id = b_submission_id;
    else
      -- Unknown type: be conservative — treat as "not equal" so conflict surfaces.
      return false;
  end case;

  -- Both null = both have no typed row = equal.
  if a_jsonb is null and b_jsonb is null then
    return true;
  end if;

  return a_jsonb is not distinct from b_jsonb;
end;
$$;

-- Read-only helper; callable by RPCs.
grant execute on function public.attribution_values_equal(uuid, uuid, text) to authenticated;
```

- [ ] **Step 2: Apply the migration**

```bash
psql "$SUPABASE_DB_URL" -f supabase/migrations/021_attribution_values_equal_fn.sql
```
Expected: `CREATE FUNCTION`, `GRANT`.

- [ ] **Step 3: Smoke-test the function**

Use two existing test submissions of the same building feature. If none, create two with identical building_attributes:

```bash
psql "$SUPABASE_DB_URL" <<'EOF'
do $$
declare
  v_aid uuid := '<TEST_ASSIGNMENT_UUID>';
  v_eid uuid := '<TEST_ENUMERATOR_UUID>';
  v_fid uuid := gen_random_uuid();
  v_s1 uuid := gen_random_uuid();
  v_s2 uuid := gen_random_uuid();
begin
  insert into public.features (id, assignment_id, feature_type, geometry, is_new)
    values (v_fid, v_aid, 'building',
            st_geographyfromtext('POINT(120.9842 14.5995)')::geometry, false);
  insert into public.submissions (id, feature_id, submitted_by, does_not_exist)
    values (v_s1, v_fid, v_eid, false), (v_s2, v_fid, v_eid, false);
  insert into public.building_attributes (submission_id, building_name, storeys, material)
    values (v_s1, 'Test Bldg', 2, 'concrete'),
           (v_s2, 'Test Bldg', 2, 'concrete');

  raise notice 'identical: %', public.attribution_values_equal(v_s1, v_s2, 'building');

  update public.building_attributes set storeys = 3 where submission_id = v_s2;
  raise notice 'after storeys change: %', public.attribution_values_equal(v_s1, v_s2, 'building');

  delete from public.submissions where id in (v_s1, v_s2);
  delete from public.features where id = v_fid;
end $$;
EOF
```
Expected NOTICEs: `identical: t`, then `after storeys change: f`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/021_attribution_values_equal_fn.sql
git commit -m "feat(db): attribution_values_equal helper for conflict detection"
```

---

## Task 8: `submit_attribution_with_conflict_check` RPC

Wraps the existing `upload_submission_bundle` with first-upload-wins + conflict-detection semantics. Returns a structured result identifying committed / agreed-skip / conflict.

**Files:**
- Create: `supabase/migrations/022_submit_attribution_conflict.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/022_submit_attribution_conflict.sql
-- Conflict-aware wrapper around upload_submission_bundle.
-- Payload shape is the same as upload_submission_bundle's, plus an
-- optional 'base_version_id' field that names the canonical submission
-- the client knew about when composing this upload.
--
-- Result JSON:
--   { status: 'committed',    submission_id }
--   { status: 'agreed_skip',  submission_id }  -- existing canonical is identical, no new row
--   { status: 'conflict',     pending_id, their_submission_id }
--
-- Pending rows: a 'conflict' result inserts the new submission rows but
-- leaves the prior canonical un-superseded. resolve_attribution then
-- either supersedes the prior (force_overwrite) or deletes the pending
-- (keep_theirs).

create or replace function public.submit_attribution_with_conflict_check(payload jsonb)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_submission jsonb := payload->'submission';
  v_feature_type text := payload->>'feature_type';
  v_base_version uuid := nullif(payload->>'base_version_id','')::uuid;
  v_submission_id uuid := (v_submission->>'id')::uuid;
  v_feature_id uuid := (v_submission->>'feature_id')::uuid;
  v_assignment_id uuid;
  v_closed boolean;
  v_current_id uuid;
  v_equal boolean;
begin
  -- Closed-assignment gate (matches upload_submission_bundle).
  select a.id, a.closed_remotely into v_assignment_id, v_closed
    from public.assignments a
    join public.features f on f.assignment_id = a.id
    where f.id = v_feature_id;

  if v_closed then
    raise exception 'assignment_closed' using errcode = '53300';
  end if;

  -- Idempotency: same submission id already inserted? Return its prior result.
  if exists (select 1 from public.submissions where id = v_submission_id) then
    -- Re-derive status. If superseded_by_id refs another row, this row is
    -- the loser. If it has superseded_at = null, it's canonical.
    return jsonb_build_object(
      'status', case
        when (select superseded_at is null from public.submissions where id = v_submission_id) then 'committed'
        else 'conflict'
      end,
      'submission_id', v_submission_id
    );
  end if;

  -- Identify the current canonical row, if any, for this feature.
  select id into v_current_id
    from public.submissions
    where feature_id = v_feature_id and superseded_at is null
    order by created_at desc
    limit 1;

  -- Case A: no prior canonical → straight insert via the existing bundle RPC.
  if v_current_id is null then
    perform public.upload_submission_bundle(payload);
    return jsonb_build_object('status','committed','submission_id', v_submission_id);
  end if;

  -- Case B: explicit override of the version the client knew about.
  if v_base_version is not null and v_base_version = v_current_id then
    -- Capture prior snapshot BEFORE we update v_current_id.
    declare v_prior_snapshot jsonb;
    begin
      select to_jsonb(s.*) into v_prior_snapshot
        from public.submissions s where s.id = v_current_id;

      perform public.upload_submission_bundle(payload);

      update public.submissions
        set superseded_at = now(),
            superseded_by_id = v_submission_id
        where id = v_current_id
          and superseded_at is null;  -- optimistic lock

      if found then
        insert into public.attribution_audit_log
          (table_name, row_id, action, performed_by, prior_snapshot)
        values ('submissions', v_current_id, 'supersede',
                (v_submission->>'submitted_by')::uuid,
                v_prior_snapshot);
        return jsonb_build_object('status','committed','submission_id', v_submission_id);
      else
        -- Concurrent supersede won — re-detect using the *current* canonical,
        -- excluding our just-inserted row so we don't compare against ourselves.
        select id into v_current_id
          from public.submissions
          where feature_id = v_feature_id
            and superseded_at is null
            and id <> v_submission_id
          order by created_at desc
          limit 1;
        -- fallthrough to value-comparison branch
      end if;
    end;
  end if;

  -- Case C: insert the pending bundle so we can compare typed values.
  -- (Idempotent if Case B already inserted via on-conflict upsert.)
  perform public.upload_submission_bundle(payload);

  -- If after a Case B race the canonical disappeared, we are now canonical.
  if v_current_id is null then
    return jsonb_build_object('status','committed','submission_id', v_submission_id);
  end if;

  -- Compare against current canonical.
  v_equal := public.attribution_values_equal(v_current_id, v_submission_id, v_feature_type);

  if v_equal then
    -- Agreement: drop the pending we just inserted and keep canonical as-is.
    delete from public.building_attributes where submission_id = v_submission_id;
    delete from public.road_attributes where submission_id = v_submission_id;
    delete from public.household_surveys where submission_id = v_submission_id;
    delete from public.submissions where id = v_submission_id;
    return jsonb_build_object('status','agreed_skip','submission_id', v_current_id);
  end if;

  -- Real conflict: leave pending row in place, do NOT supersede current.
  return jsonb_build_object(
    'status','conflict',
    'pending_id', v_submission_id,
    'their_submission_id', v_current_id
  );
end;
$$;

grant execute on function public.submit_attribution_with_conflict_check(jsonb) to authenticated;
```

- [ ] **Step 2: Apply the migration**

```bash
psql "$SUPABASE_DB_URL" -f supabase/migrations/022_submit_attribution_conflict.sql
```
Expected: `CREATE FUNCTION`, `GRANT`.

- [ ] **Step 3: Smoke-test the three outcomes**

```bash
psql "$SUPABASE_DB_URL" <<'EOF'
do $$
declare
  v_aid uuid := '<TEST_ASSIGNMENT_UUID>';
  v_e1 uuid := '<ENUMERATOR_A_UUID>';
  v_e2 uuid := '<ENUMERATOR_B_UUID>';
  v_fid uuid := gen_random_uuid();
  v_s1 uuid := gen_random_uuid();
  v_s2 uuid := gen_random_uuid();
  v_s3 uuid := gen_random_uuid();
  v_result jsonb;
begin
  insert into public.features (id, assignment_id, feature_type, geometry, is_new)
    values (v_fid, v_aid, 'building',
            st_geographyfromtext('POINT(120.9842 14.5995)')::geometry, false);

  -- 1) First submission → committed.
  v_result := public.submit_attribution_with_conflict_check(jsonb_build_object(
    'feature_type','building',
    'submission', jsonb_build_object(
      'id', v_s1, 'feature_id', v_fid, 'submitted_by', v_e1,
      'does_not_exist', false, 'remarks', null, 'override_reason', null,
      'created_at', now(), 'updated_at', now()),
    'building_attributes', jsonb_build_object(
      'submission_id', v_s1, 'building_name', 'A', 'storeys', 2, 'material', 'concrete',
      'cost_is_exact', false, 'cost_amount', null, 'cost_estimate_range', null,
      'cbms_id', null, 'ra_9514_type', null,
      'fire_fighting_facilities', '[]'::jsonb, 'fire_load', '[]'::jsonb)
  ));
  raise notice '1) committed: %', v_result;

  -- 2) Identical second submission by another user → agreed_skip.
  v_result := public.submit_attribution_with_conflict_check(jsonb_build_object(
    'feature_type','building',
    'submission', jsonb_build_object(
      'id', v_s2, 'feature_id', v_fid, 'submitted_by', v_e2,
      'does_not_exist', false, 'remarks', null, 'override_reason', null,
      'created_at', now(), 'updated_at', now()),
    'building_attributes', jsonb_build_object(
      'submission_id', v_s2, 'building_name', 'A', 'storeys', 2, 'material', 'concrete',
      'cost_is_exact', false, 'cost_amount', null, 'cost_estimate_range', null,
      'cbms_id', null, 'ra_9514_type', null,
      'fire_fighting_facilities', '[]'::jsonb, 'fire_load', '[]'::jsonb)
  ));
  raise notice '2) agreed_skip: %', v_result;

  -- 3) Differing third submission by another user → conflict.
  v_result := public.submit_attribution_with_conflict_check(jsonb_build_object(
    'feature_type','building',
    'submission', jsonb_build_object(
      'id', v_s3, 'feature_id', v_fid, 'submitted_by', v_e2,
      'does_not_exist', false, 'remarks', null, 'override_reason', null,
      'created_at', now(), 'updated_at', now()),
    'building_attributes', jsonb_build_object(
      'submission_id', v_s3, 'building_name', 'A', 'storeys', 3, 'material', 'concrete',
      'cost_is_exact', false, 'cost_amount', null, 'cost_estimate_range', null,
      'cbms_id', null, 'ra_9514_type', null,
      'fire_fighting_facilities', '[]'::jsonb, 'fire_load', '[]'::jsonb)
  ));
  raise notice '3) conflict: %', v_result;

  delete from public.submissions where feature_id = v_fid;
  delete from public.features where id = v_fid;
end $$;
EOF
```
Expected NOTICEs:
- `1) committed: {"status": "committed", "submission_id": "<v_s1>"}`
- `2) agreed_skip: {"status": "agreed_skip", "submission_id": "<v_s1>"}`
- `3) conflict: {"status": "conflict", "pending_id": "<v_s3>", "their_submission_id": "<v_s1>"}`

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/022_submit_attribution_conflict.sql
git commit -m "feat(db): submit_attribution_with_conflict_check RPC"
```

---

## Task 9: `submit_new_feature_with_dedup_check` RPC

Wraps `upload_new_feature` with proximity-flagging. Returns `committed` or `dedup_pending` based on the trigger-populated `possible_duplicate_of`.

**Files:**
- Create: `supabase/migrations/023_submit_new_feature_dedup.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/023_submit_new_feature_dedup.sql
-- Wraps upload_new_feature with dedup awareness. The proximity trigger
-- (migration 019) populates features.possible_duplicate_of on insert.
-- This RPC inspects that column and returns the appropriate response.
--
-- Payload: same as upload_new_feature.
--
-- Result JSON:
--   { status: 'committed',     feature_id }
--   { status: 'dedup_pending', pending_id, possible_duplicate_of }

create or replace function public.submit_new_feature_with_dedup_check(payload jsonb)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_id uuid := (payload->>'id')::uuid;
  v_duplicate_of uuid;
begin
  -- Idempotency: re-derive status from existing row if already inserted.
  if exists (select 1 from public.features where id = v_id) then
    select possible_duplicate_of into v_duplicate_of
      from public.features where id = v_id;
    if v_duplicate_of is null then
      return jsonb_build_object('status','committed','feature_id', v_id);
    else
      return jsonb_build_object(
        'status','dedup_pending',
        'pending_id', v_id,
        'possible_duplicate_of', v_duplicate_of
      );
    end if;
  end if;

  perform public.upload_new_feature(payload);

  select possible_duplicate_of into v_duplicate_of
    from public.features where id = v_id;

  if v_duplicate_of is null then
    return jsonb_build_object('status','committed','feature_id', v_id);
  else
    return jsonb_build_object(
      'status','dedup_pending',
      'pending_id', v_id,
      'possible_duplicate_of', v_duplicate_of
    );
  end if;
end;
$$;

grant execute on function public.submit_new_feature_with_dedup_check(jsonb) to authenticated;
```

- [ ] **Step 2: Apply the migration**

```bash
psql "$SUPABASE_DB_URL" -f supabase/migrations/023_submit_new_feature_dedup.sql
```
Expected: `CREATE FUNCTION`, `GRANT`.

- [ ] **Step 3: Smoke-test the two outcomes**

```bash
psql "$SUPABASE_DB_URL" <<'EOF'
do $$
declare
  v_aid uuid := '<TEST_ASSIGNMENT_UUID>';
  v_f1 uuid := gen_random_uuid();
  v_f2 uuid := gen_random_uuid();
  v_r1 jsonb;
  v_r2 jsonb;
begin
  v_r1 := public.submit_new_feature_with_dedup_check(jsonb_build_object(
    'id', v_f1, 'assignment_id', v_aid, 'feature_type','building',
    'geometry_geojson', '{"type":"Point","coordinates":[120.9842,14.5995]}',
    'is_new', true));
  raise notice '1) committed: %', v_r1;

  v_r2 := public.submit_new_feature_with_dedup_check(jsonb_build_object(
    'id', v_f2, 'assignment_id', v_aid, 'feature_type','building',
    'geometry_geojson', '{"type":"Point","coordinates":[120.98421,14.5995]}',
    'is_new', true));
  raise notice '2) dedup_pending: %', v_r2;

  delete from public.features where id in (v_f1, v_f2);
end $$;
EOF
```
Expected NOTICEs:
- `1) committed: {"status": "committed", "feature_id": "<v_f1>"}`
- `2) dedup_pending: {"status": "dedup_pending", "pending_id": "<v_f2>", "possible_duplicate_of": "<v_f1>"}`

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/023_submit_new_feature_dedup.sql
git commit -m "feat(db): submit_new_feature_with_dedup_check RPC"
```

---

## Task 10: `resolve_attribution` and `resolve_new_feature` RPCs

The two resolution RPCs the client calls after the user reviews a conflict or dedup item. Both write to the audit log.

**Files:**
- Create: `supabase/migrations/024_resolve_rpcs.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/024_resolve_rpcs.sql
-- Resolution RPCs called after user review.
--
-- resolve_attribution(pending_id, decision):
--   decision in ('keep_theirs','force_overwrite')
--   keep_theirs    → delete pending row + children. Returns { resolved: 'keep_theirs',
--                                                            canonical_submission_id }.
--   force_overwrite→ supersede the prior canonical with the pending, audit. Returns
--                    { resolved: 'force_overwrite', canonical_submission_id: pending_id }.
--
-- resolve_new_feature(pending_id, decision):
--   decision in ('keep_both','replace_theirs','discard_mine')
--   keep_both       → just set dedup_reviewed_at. Returns { resolved: 'keep_both' }.
--   replace_theirs  → soft-delete the older feature (mark its latest submission
--                     superseded with null replacement), audit. Returns { resolved: 'replace_theirs' }.
--   discard_mine    → soft-delete the pending feature similarly, audit. Returns { resolved: 'discard_mine' }.

create or replace function public.resolve_attribution(
  pending_id uuid,
  decision text,
  resolution_note text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_feature_id uuid;
  v_actor uuid := auth.uid();
  v_prior_id uuid;
begin
  if decision not in ('keep_theirs','force_overwrite') then
    raise exception 'invalid_decision: %', decision using errcode='22023';
  end if;

  select feature_id into v_feature_id
    from public.submissions where id = pending_id;
  if v_feature_id is null then
    raise exception 'pending_not_found' using errcode='P0002';
  end if;

  -- Current canonical (anyone non-superseded other than pending).
  select id into v_prior_id
    from public.submissions
    where feature_id = v_feature_id
      and superseded_at is null
      and id <> pending_id
    order by created_at desc
    limit 1;

  if decision = 'keep_theirs' then
    -- The pending row was never canonical; deleting it is a withdraw, not an
    -- audit-worthy supersede of canonical state. No audit row written.
    delete from public.building_attributes where submission_id = pending_id;
    delete from public.road_attributes where submission_id = pending_id;
    delete from public.household_surveys where submission_id = pending_id;
    delete from public.submissions where id = pending_id;

    return jsonb_build_object('resolved','keep_theirs',
                              'canonical_submission_id', v_prior_id);
  end if;

  -- force_overwrite
  if v_prior_id is null then
    -- Nothing to supersede — treat as committed.
    return jsonb_build_object('resolved','force_overwrite',
                              'canonical_submission_id', pending_id);
  end if;

  -- Snapshot prior values BEFORE the update so the audit reflects pre-state.
  declare v_prior_snapshot jsonb;
  begin
    select to_jsonb(s.*) into v_prior_snapshot
      from public.submissions s where s.id = v_prior_id;

    update public.submissions
      set superseded_at = now(),
          superseded_by_id = pending_id
      where id = v_prior_id
        and superseded_at is null;
    if not found then
      raise exception 'concurrent_supersede_lost_race' using errcode='40001';
    end if;

    insert into public.attribution_audit_log
      (table_name, row_id, action, performed_by, prior_snapshot, resolution_note)
    values ('submissions', v_prior_id, 'force_overwrite',
            v_actor, v_prior_snapshot, resolution_note);
  end;

  return jsonb_build_object('resolved','force_overwrite',
                            'canonical_submission_id', pending_id);
end;
$$;

grant execute on function public.resolve_attribution(uuid, text, text) to authenticated;


create or replace function public.resolve_new_feature(
  pending_id uuid,
  decision text,
  resolution_note text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_dup_of uuid;
  v_actor uuid := auth.uid();
  v_to_soft_delete uuid;
  v_other uuid;
  v_prior jsonb;
  v_latest_sub uuid;
begin
  if decision not in ('keep_both','replace_theirs','discard_mine') then
    raise exception 'invalid_decision: %', decision using errcode='22023';
  end if;

  select possible_duplicate_of into v_dup_of
    from public.features where id = pending_id;

  if v_dup_of is null and decision <> 'keep_both' then
    raise exception 'no_duplicate_to_resolve' using errcode='22023';
  end if;

  if decision = 'keep_both' then
    -- Snapshot the pending feature's prior state before flipping dedup_reviewed_at.
    select to_jsonb(f.*) into v_prior
      from public.features f where f.id = pending_id;
    update public.features set dedup_reviewed_at = now() where id = pending_id;
    insert into public.attribution_audit_log
      (table_name, row_id, action, performed_by, prior_snapshot, resolution_note)
    values ('features', pending_id, 'dedup_resolve',
            v_actor, v_prior, coalesce(resolution_note,'keep_both'));
    return jsonb_build_object('resolved','keep_both');
  end if;

  if decision = 'replace_theirs' then
    v_to_soft_delete := v_dup_of;
    v_other := pending_id;
  else  -- discard_mine
    v_to_soft_delete := pending_id;
    v_other := v_dup_of;
  end if;

  -- Snapshot the feature we're about to soft-delete *before* any updates touch it.
  select to_jsonb(f.*) into v_prior
    from public.features f where f.id = v_to_soft_delete;

  -- Find the latest non-superseded submission on the feature we're soft-deleting.
  select id into v_latest_sub
    from public.submissions
    where feature_id = v_to_soft_delete and superseded_at is null
    order by created_at desc limit 1;

  if v_latest_sub is not null then
    update public.submissions
      set superseded_at = now(),
          superseded_by_id = null   -- null = "discarded", not "replaced by"
      where id = v_latest_sub;
  end if;

  -- Mark both features as reviewed.
  update public.features set dedup_reviewed_at = now() where id = v_other;
  update public.features set dedup_reviewed_at = now() where id = v_to_soft_delete;

  insert into public.attribution_audit_log
    (table_name, row_id, action, performed_by, prior_snapshot, resolution_note)
    values ('features', v_to_soft_delete, 'dedup_resolve',
            v_actor, v_prior, coalesce(resolution_note, decision));

  return jsonb_build_object('resolved', decision);
end;
$$;

grant execute on function public.resolve_new_feature(uuid, text, text) to authenticated;
```

- [ ] **Step 2: Apply the migration**

```bash
psql "$SUPABASE_DB_URL" -f supabase/migrations/024_resolve_rpcs.sql
```
Expected: 2× `CREATE FUNCTION`, 2× `GRANT`.

- [ ] **Step 3: Test `resolve_attribution` — `keep_theirs` path**

```bash
psql "$SUPABASE_DB_URL" <<'EOF'
do $$
declare
  v_aid uuid := '<TEST_ASSIGNMENT_UUID>';
  v_e1 uuid := '<ENUMERATOR_A_UUID>';
  v_e2 uuid := '<ENUMERATOR_B_UUID>';
  v_fid uuid := gen_random_uuid();
  v_s1 uuid := gen_random_uuid();
  v_s2 uuid := gen_random_uuid();
  v_result jsonb;
begin
  insert into public.features (id, assignment_id, feature_type, geometry, is_new)
    values (v_fid, v_aid, 'building',
            st_geographyfromtext('POINT(120.9842 14.5995)')::geometry, false);

  -- Canonical
  insert into public.submissions (id, feature_id, submitted_by, does_not_exist)
    values (v_s1, v_fid, v_e1, false);
  insert into public.building_attributes (submission_id, storeys) values (v_s1, 2);

  -- Pending
  insert into public.submissions (id, feature_id, submitted_by, does_not_exist)
    values (v_s2, v_fid, v_e2, false);
  insert into public.building_attributes (submission_id, storeys) values (v_s2, 3);

  v_result := public.resolve_attribution(v_s2, 'keep_theirs', 'test');
  raise notice 'keep_theirs result: %', v_result;
  raise notice 'pending row gone? %', (select not exists (select 1 from public.submissions where id = v_s2));
  raise notice 'canonical still: %', (select s.id from public.submissions s where s.id = v_s1 and s.superseded_at is null);

  delete from public.submissions where feature_id = v_fid;
  delete from public.features where id = v_fid;
end $$;
EOF
```
Expected NOTICEs:
- `keep_theirs result: {"resolved": "keep_theirs", "canonical_submission_id": "<v_s1>"}`
- `pending row gone? t`
- `canonical still: <v_s1>`

- [ ] **Step 4: Test `resolve_attribution` — `force_overwrite` path**

```bash
psql "$SUPABASE_DB_URL" <<'EOF'
do $$
declare
  v_aid uuid := '<TEST_ASSIGNMENT_UUID>';
  v_e1 uuid := '<ENUMERATOR_A_UUID>';
  v_e2 uuid := '<ENUMERATOR_B_UUID>';
  v_fid uuid := gen_random_uuid();
  v_s1 uuid := gen_random_uuid();
  v_s2 uuid := gen_random_uuid();
  v_result jsonb;
  v_audit_count int;
begin
  insert into public.features (id, assignment_id, feature_type, geometry, is_new)
    values (v_fid, v_aid, 'building',
            st_geographyfromtext('POINT(120.9842 14.5995)')::geometry, false);
  insert into public.submissions (id, feature_id, submitted_by, does_not_exist)
    values (v_s1, v_fid, v_e1, false);
  insert into public.building_attributes (submission_id, storeys) values (v_s1, 2);
  insert into public.submissions (id, feature_id, submitted_by, does_not_exist)
    values (v_s2, v_fid, v_e2, false);
  insert into public.building_attributes (submission_id, storeys) values (v_s2, 3);

  v_result := public.resolve_attribution(v_s2, 'force_overwrite', 'test');
  raise notice 'force_overwrite: %', v_result;
  raise notice 's1 superseded? %', (select superseded_at is not null from public.submissions where id = v_s1);
  raise notice 's1 superseded_by? %', (select superseded_by_id from public.submissions where id = v_s1);

  select count(*) into v_audit_count from public.attribution_audit_log
    where row_id = v_s1 and action = 'force_overwrite';
  raise notice 'audit rows for s1: %', v_audit_count;

  delete from public.attribution_audit_log where row_id = v_s1;
  delete from public.submissions where feature_id = v_fid;
  delete from public.features where id = v_fid;
end $$;
EOF
```
Expected NOTICEs:
- `force_overwrite: {"resolved": "force_overwrite", "canonical_submission_id": "<v_s2>"}`
- `s1 superseded? t`
- `s1 superseded_by? <v_s2>`
- `audit rows for s1: 1`

- [ ] **Step 5: Test `resolve_new_feature` — `replace_theirs` path**

```bash
psql "$SUPABASE_DB_URL" <<'EOF'
do $$
declare
  v_aid uuid := '<TEST_ASSIGNMENT_UUID>';
  v_f1 uuid := gen_random_uuid();
  v_f2 uuid := gen_random_uuid();
  v_result jsonb;
begin
  insert into public.features (id, assignment_id, feature_type, geometry, is_new)
    values (v_f1, v_aid, 'building',
            st_geographyfromtext('POINT(120.9842 14.5995)')::geometry, true);
  insert into public.features (id, assignment_id, feature_type, geometry, is_new)
    values (v_f2, v_aid, 'building',
            st_geographyfromtext('POINT(120.98421 14.5995)')::geometry, true);
  -- f2 should have possible_duplicate_of = f1 (from trigger).

  v_result := public.resolve_new_feature(v_f2, 'replace_theirs', 'test');
  raise notice 'replace_theirs: %', v_result;
  raise notice 'f1 dedup_reviewed: %', (select dedup_reviewed_at is not null from public.features where id = v_f1);
  raise notice 'f2 dedup_reviewed: %', (select dedup_reviewed_at is not null from public.features where id = v_f2);

  delete from public.attribution_audit_log where row_id in (v_f1, v_f2);
  delete from public.features where id in (v_f1, v_f2);
end $$;
EOF
```
Expected NOTICEs:
- `replace_theirs: {"resolved": "replace_theirs"}`
- `f1 dedup_reviewed: t`
- `f2 dedup_reviewed: t`

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/024_resolve_rpcs.sql
git commit -m "feat(db): resolve_attribution + resolve_new_feature RPCs"
```

---

## Task 11: Realtime publication for `submissions` + `features`

Adds the two canonical tables to the `supabase_realtime` publication so clients can subscribe. Supabase auto-applies RLS on realtime, so only assignment members will see events.

**Files:**
- Create: `supabase/migrations/025_realtime_publication.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/025_realtime_publication.sql
-- Adds submissions and features to the supabase_realtime publication so
-- clients can subscribe. RLS applies automatically — non-members of an
-- assignment will not receive events for rows scoped to that assignment.
--
-- Safe to re-run: alter publication add table is idempotent only via
-- not exists check, so we wrap each in a do block.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'submissions'
  ) then
    alter publication supabase_realtime add table public.submissions;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'features'
  ) then
    alter publication supabase_realtime add table public.features;
  end if;
end $$;

-- Replica identity FULL needed so realtime emits the *old* row on UPDATE,
-- which the client uses to detect supersede transitions (superseded_at: null → not null).
alter table public.submissions replica identity full;
alter table public.features    replica identity full;
```

- [ ] **Step 2: Apply the migration**

```bash
psql "$SUPABASE_DB_URL" -f supabase/migrations/025_realtime_publication.sql
```
Expected: `DO`, 2× `ALTER TABLE`.

- [ ] **Step 3: Verify publication membership**

```bash
psql "$SUPABASE_DB_URL" -c "
  select tablename from pg_publication_tables
  where pubname = 'supabase_realtime'
    and schemaname = 'public'
    and tablename in ('submissions','features')
  order by tablename;
"
```
Expected: 2 rows — `features`, `submissions`.

- [ ] **Step 4: Verify replica identity**

```bash
psql "$SUPABASE_DB_URL" -c "
  select c.relname, c.relreplident
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in ('submissions','features');
"
```
Expected: `relreplident = 'f'` (full) for both rows.

- [ ] **Step 5: Smoke-test from a Supabase realtime client (optional, recommended)**

Open the Supabase Studio "Realtime" tab (or a small Dart/JS script), subscribe to `public:submissions` filtered by an assignment your test user is a member of, then `INSERT` a row into `submissions` from another psql session and confirm the event arrives in the subscriber within a few seconds. If no event arrives, check `pg_publication_tables`, replica identity, and RLS membership for the subscribing user.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/025_realtime_publication.sql
git commit -m "feat(db): publish submissions + features on supabase_realtime"
```

---

## Phase 1 Acceptance Checklist

When all 11 tasks above are committed, the following should be true:

- [ ] `assignment_members` table exists; every existing assignment has exactly one `'owner'` row backfilled from `assignments.enumerator_id`.
- [ ] All seven previously single-owner tables (`assignments`, `features`, `submissions`, three typed-attribute tables, `photos`) use membership-based RLS policies named `*_via_membership_rw` (or `assignments_member_rw`).
- [ ] `submissions` has `superseded_at`, `superseded_by_id`, plus the two new indexes.
- [ ] `features` has `possible_duplicate_of`, `dedup_reviewed_at`, generated `centroid`, and the GIST index.
- [ ] `assignments.dedup_proximity_meters` exists with default 5.
- [ ] Trigger `trg_features_dedup` populates `possible_duplicate_of` only when `is_new = true`.
- [ ] `attribution_audit_log` exists with insert-only RPC writes and membership-scoped read RLS.
- [ ] `attribution_values_equal(uuid, uuid, text)` returns true for identical typed-child rows, false otherwise.
- [ ] `submit_attribution_with_conflict_check` returns `committed` / `agreed_skip` / `conflict` for the three scenarios.
- [ ] `submit_new_feature_with_dedup_check` returns `committed` for isolated inserts and `dedup_pending` for nearby same-type inserts.
- [ ] `resolve_attribution` produces correct supersede + audit rows for `force_overwrite`, and removes the pending row for `keep_theirs`.
- [ ] `resolve_new_feature` correctly soft-deletes the chosen feature and records audit for `replace_theirs` / `discard_mine`.
- [ ] `supabase_realtime` publication includes both `submissions` and `features` with replica identity full.

No client code has changed at this point. The existing `upload_submission_bundle` / `upload_new_feature` RPCs continue to work for existing single-user uploads.

---

## What's Next

Phase 1 is one of five phases derived from the spec's migration plan. The next phases will each get their own implementation plan:

- **Phase 2:** Client cache schemas + cold-open / reconnect pull (Drift tables, repositories; no UI).
- **Phase 3:** Realtime subscription + connection state machine.
- **Phase 4:** Map badge UI driven by the cache.
- **Phase 5:** Push migration to the new RPCs + conflict review UI + new-feature dedup UI.
- **Phase 6:** Decommission old upload path.

Each phase produces independently shippable software per the spec's migration plan section.
