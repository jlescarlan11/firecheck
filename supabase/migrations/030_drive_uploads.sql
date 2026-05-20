-- supabase/migrations/030_drive_uploads.sql
-- Tracks which enumerator uploaded an assignment's artifacts to Google Drive,
-- so other members of the same assignment can be warned before re-uploading.
--
-- Append-only audit log: rows are never updated or deleted by clients.
-- One row per upload attempt that completed successfully on the client side.

begin;

create table public.drive_uploads (
  id                 uuid primary key default gen_random_uuid(),
  assignment_id      uuid not null references public.assignments(id) on delete cascade,
  uploaded_by        uuid not null references public.enumerators(id),
  drive_folder_path  text not null,
  drive_folder_url   text not null default '',
  file_count         integer not null default 0,
  uploaded_at        timestamptz not null default now()
);

create index drive_uploads_by_assignment
  on public.drive_uploads (assignment_id, uploaded_at desc);

alter table public.drive_uploads enable row level security;

-- Members of an assignment can read its upload history.
drop policy if exists drive_uploads_member_read on public.drive_uploads;
create policy drive_uploads_member_read on public.drive_uploads
  for select
  using (
    exists (
      select 1 from public.assignment_members am
      where am.assignment_id = drive_uploads.assignment_id
        and am.enumerator_id = auth.uid()
    )
  );

-- Members can record their own uploads (uploaded_by must match auth.uid()).
drop policy if exists drive_uploads_member_insert on public.drive_uploads;
create policy drive_uploads_member_insert on public.drive_uploads
  for insert
  with check (
    uploaded_by = auth.uid()
    and exists (
      select 1 from public.assignment_members am
      where am.assignment_id = drive_uploads.assignment_id
        and am.enumerator_id = auth.uid()
    )
  );

-- No UPDATE or DELETE policies: audit log is append-only from the client.

commit;
