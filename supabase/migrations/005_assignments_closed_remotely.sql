-- Phase 4a: assignment-closed-remotely flag for 409 path.
alter table public.assignments
  add column closed_remotely boolean not null default false;
