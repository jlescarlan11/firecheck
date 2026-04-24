-- Phase 2: distance-rule Override flow records a free-text reason that
-- supervisors review during sync.
alter table public.submissions add column override_reason text;
