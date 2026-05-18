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
