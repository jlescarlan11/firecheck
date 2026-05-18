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
