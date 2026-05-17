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
