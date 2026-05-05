-- supabase/migrations/014_download_events.sql
-- Logs every shapefile download with per-file granularity.
-- file_id is the Drive file ID — assignments can contain multiple files.
-- Index on (enumerator_id, created_at desc) supports "recent activity" queries.
create table public.download_events (
  id            uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments(id) on delete cascade,
  file_id       text not null,
  enumerator_id uuid not null references public.enumerators(id) on delete cascade,
  created_at    timestamptz not null default now()
);

create index download_events_enumerator_activity
  on public.download_events (enumerator_id, created_at desc);
