begin;

-- FireCheck has no signed-out data flows. Supabase grants Data API table
-- privileges to anon by default, so remove that unnecessary surface and let
-- authenticated access continue to be constrained by each table's RLS.
revoke all on table public.enumerators from anon;
revoke all on table public.ra_9514_types from anon;
revoke all on table public.assignments from anon;
revoke all on table public.assignment_members from anon;
revoke all on table public.features from anon;
revoke all on table public.feature_geometry_revisions from anon;
revoke all on table public.submissions from anon;
revoke all on table public.building_attributes from anon;
revoke all on table public.road_attributes from anon;
revoke all on table public.household_surveys from anon;
revoke all on table public.photos from anon;
revoke all on table public.attribution_audit_log from anon;
revoke all on table public.download_events from anon;
revoke all on table public.drive_uploads from anon;

-- Download events were the only FireCheck table created without RLS.
alter table public.download_events enable row level security;

drop policy if exists download_events_self_read
  on public.download_events;
create policy download_events_self_read
  on public.download_events
  for select
  to authenticated
  using ((select auth.uid()) = enumerator_id);

drop policy if exists download_events_member_insert
  on public.download_events;
create policy download_events_member_insert
  on public.download_events
  for insert
  to authenticated
  with check (
    (select auth.uid()) = enumerator_id
    and exists (
      select 1
      from public.assignment_members am
      where am.assignment_id = download_events.assignment_id
        and am.enumerator_id = (select auth.uid())
    )
  );

revoke update, delete, truncate, references, trigger
  on table public.download_events from authenticated;
grant select, insert on table public.download_events to authenticated;

-- SECURITY DEFINER RPCs must never inherit Supabase's automatic anon execute
-- grant. App-facing RPCs are authenticated; maintenance functions are kept
-- service-role-only; trigger functions remain callable only by their owner.
revoke execute on function public.upload_submission_bundle(jsonb)
  from public, anon;
revoke execute on function public.upload_new_feature(jsonb)
  from public, anon;
revoke execute on function public.update_feature_geometry(
  uuid, uuid, text, text, timestamptz, text
) from public, anon;
revoke execute on function public.submit_attribution_with_conflict_check(jsonb)
  from public, anon;
revoke execute on function public.submit_new_feature_with_dedup_check(jsonb)
  from public, anon;
revoke execute on function public.resolve_attribution(uuid, text, text)
  from public, anon;
revoke execute on function public.resolve_new_feature(uuid, text, text)
  from public, anon;
revoke execute on function public.resolve_assignment_id_by_name(text)
  from public, anon;
revoke execute on function public.claim_assignment_by_name(text)
  from public, anon;
revoke execute on function public.bulk_upsert_features(uuid, jsonb)
  from public, anon;

grant execute on function public.upload_submission_bundle(jsonb)
  to authenticated;
grant execute on function public.upload_new_feature(jsonb)
  to authenticated;
grant execute on function public.update_feature_geometry(
  uuid, uuid, text, text, timestamptz, text
) to authenticated;
grant execute on function public.submit_attribution_with_conflict_check(jsonb)
  to authenticated;
grant execute on function public.submit_new_feature_with_dedup_check(jsonb)
  to authenticated;
grant execute on function public.resolve_attribution(uuid, text, text)
  to authenticated;
grant execute on function public.resolve_new_feature(uuid, text, text)
  to authenticated;
grant execute on function public.resolve_assignment_id_by_name(text)
  to authenticated;
grant execute on function public.claim_assignment_by_name(text)
  to authenticated;
grant execute on function public.bulk_upsert_features(uuid, jsonb)
  to authenticated;

revoke execute on function public.cleanup_orphan_photos()
  from public, anon, authenticated;
grant execute on function public.cleanup_orphan_photos()
  to service_role;

revoke execute on function public.handle_new_enumerator()
  from public, anon, authenticated;

commit;
