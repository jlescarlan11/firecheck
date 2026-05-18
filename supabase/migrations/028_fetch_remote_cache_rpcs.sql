-- supabase/migrations/028_fetch_remote_cache_rpcs.sql
-- Phase 2 of multi-user attribution sync: server endpoints that feed the
-- client-side remote_*_cache Drift tables.
--
-- We expose two read-only RPCs:
--
--   fetch_remote_attributions(p_assignment_id, p_since)
--     Returns submissions joined with their typed child-table rows shaped as
--     jsonb under `attribute_values`. One round-trip replaces an N+1 join
--     dance on the client. `p_since` is the client's cursor; null on cold-
--     open. The response is ordered by updated_at asc, and the client uses
--     `max(updated_at)` of the response as the next cursor — not now() —
--     so replication lag / clock skew can't lose events.
--
--   fetch_remote_new_features(p_assignment_id, p_since)
--     Same shape for `features where is_new = true`, with geometry as
--     GeoJSON text (the existing client renderer expects geojson, not WKB).
--
-- RLS: SECURITY INVOKER. The membership-scoped policies from migration 016
-- already restrict select on submissions/features. A non-member sees an
-- empty array.
--
-- Features need an `updated_at` column to support the delta cursor — added
-- here with a BEFORE UPDATE trigger that maintains it.

-- ============================================================
-- features.updated_at
-- ============================================================
alter table public.features
  add column if not exists updated_at timestamptz not null default now();

create or replace function public.set_features_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists trg_features_updated_at on public.features;
create trigger trg_features_updated_at
  before update on public.features
  for each row execute function public.set_features_updated_at();

create index if not exists features_assignment_updated_at_idx
  on public.features (assignment_id, updated_at);

-- Backfill existing rows so the delta cursor doesn't miss them on first pull.
update public.features set updated_at = coalesce(updated_at, created_at) where updated_at is null;

create index if not exists submissions_assignment_updated_at_idx
  on public.submissions (updated_at);

-- ============================================================
-- fetch_remote_attributions
-- ============================================================
create or replace function public.fetch_remote_attributions(
  p_assignment_id uuid,
  p_since timestamptz default null
) returns jsonb
language sql
stable
security invoker
as $$
  select coalesce(jsonb_agg(row order by (row->>'updated_at')), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id',               s.id,
      'feature_id',       s.feature_id,
      'feature_type',     f.feature_type::text,
      'submitted_by',     s.submitted_by,
      'submitted_at',     s.created_at,
      'superseded_at',    s.superseded_at,
      'superseded_by_id', s.superseded_by_id,
      'updated_at',       s.updated_at,
      'attribute_values', jsonb_build_object(
        'does_not_exist',  s.does_not_exist,
        'remarks',         s.remarks,
        'override_reason', s.override_reason,
        'building',        case when b.submission_id is null then null
                                else to_jsonb(b.*) - 'submission_id' end,
        'road',            case when r.submission_id is null then null
                                else to_jsonb(r.*) - 'submission_id' end,
        'household',       case when h.submission_id is null then null
                                else to_jsonb(h.*) - 'submission_id' end
      )
    ) as row
    from public.submissions s
    join public.features f on f.id = s.feature_id
    left join public.building_attributes b on b.submission_id = s.id
    left join public.road_attributes     r on r.submission_id = s.id
    left join public.household_surveys   h on h.submission_id = s.id
    where f.assignment_id = p_assignment_id
      and (p_since is null or s.updated_at > p_since)
  ) t;
$$;

grant execute on function public.fetch_remote_attributions(uuid, timestamptz) to authenticated;

-- ============================================================
-- fetch_remote_new_features
-- ============================================================
-- For new features we additionally surface the first submission's
-- submitted_by/submitted_at so the cache row carries an "added by Alice"
-- attribution without a second round-trip.
create or replace function public.fetch_remote_new_features(
  p_assignment_id uuid,
  p_since timestamptz default null
) returns jsonb
language sql
stable
security invoker
as $$
  with first_sub as (
    select distinct on (feature_id)
      feature_id,
      submitted_by,
      created_at as submitted_at,
      superseded_at,
      superseded_by_id
    from public.submissions
    order by feature_id, created_at asc
  )
  select coalesce(jsonb_agg(row order by (row->>'updated_at')), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id',                    f.id,
      'assignment_id',         f.assignment_id,
      'feature_type',          f.feature_type::text,
      'geometry_geojson',      st_asgeojson(f.geometry::geometry),
      'centroid_lat',          st_y(f.centroid::geometry),
      'centroid_lng',          st_x(f.centroid::geometry),
      'submitted_by',          fs.submitted_by,
      'submitted_at',          coalesce(fs.submitted_at, f.created_at),
      'possible_duplicate_of', f.possible_duplicate_of,
      'dedup_reviewed_at',     f.dedup_reviewed_at,
      'superseded_at',         fs.superseded_at,
      'superseded_by_id',      fs.superseded_by_id,
      'updated_at',            f.updated_at
    ) as row
    from public.features f
    left join first_sub fs on fs.feature_id = f.id
    where f.assignment_id = p_assignment_id
      and f.is_new = true
      and (p_since is null or f.updated_at > p_since)
  ) t;
$$;

grant execute on function public.fetch_remote_new_features(uuid, timestamptz) to authenticated;
