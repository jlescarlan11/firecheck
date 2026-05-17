-- supabase/migrations/020_attribution_audit_log.sql
-- Records every supersede / force-overwrite / dedup-resolve event with the
-- pre-change row snapshot. Insert-only via RPCs. Readable by assignment members.

create table public.attribution_audit_log (
  id              uuid primary key default gen_random_uuid(),
  table_name      text not null check (table_name in ('submissions','features')),
  row_id          uuid not null,
  action          text not null check (action in ('supersede','force_overwrite','dedup_resolve')),
  performed_by    uuid not null references public.enumerators(id) on delete set null,
  performed_at    timestamptz not null default now(),
  prior_snapshot  jsonb not null,
  resolution_note text
);

create index attribution_audit_log_by_row
  on public.attribution_audit_log (row_id);

create index attribution_audit_log_by_actor
  on public.attribution_audit_log (performed_by, performed_at desc);

alter table public.attribution_audit_log enable row level security;

-- Members of the assignment that the audited row belongs to may select.
-- (table_name disambiguates the parent join.)
create policy audit_log_via_membership_read on public.attribution_audit_log
  for select
  using (
    case table_name
      when 'submissions' then
        exists (
          select 1 from public.submissions s
          join public.features f on f.id = s.feature_id
          join public.assignment_members am on am.assignment_id = f.assignment_id
          where s.id = attribution_audit_log.row_id
            and am.enumerator_id = auth.uid()
        )
      when 'features' then
        exists (
          select 1 from public.features f
          join public.assignment_members am on am.assignment_id = f.assignment_id
          where f.id = attribution_audit_log.row_id
            and am.enumerator_id = auth.uid()
        )
      else false
    end
  );

-- INSERTs come only from security-definer RPCs (no client policy).
