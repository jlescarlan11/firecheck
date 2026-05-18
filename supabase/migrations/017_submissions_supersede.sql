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
