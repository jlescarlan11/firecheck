-- Phase 3b: add homeowner acknowledgement + completion timestamp to household_surveys.
alter table public.household_surveys
  add column homeowner_acknowledged boolean not null default false;
alter table public.household_surveys
  add column completed_at timestamptz null;
