-- supabase/migrations/029_cleanup_orphan_photos.sql
-- Scheduled cleanup of orphaned photo storage objects.
--
-- Orphans accumulate from the conflict / dedup review flows:
--   * `agreed_skip` deletes the loser's `submissions` row outright
--     (and its `building_attributes` / `road_attributes` / `household_surveys`),
--     cascading to its `photos` rows via `on delete cascade`. The storage
--     objects under bucket `photos` survive the cascade.
--   * `resolve_attribution(keep_theirs)` deletes the pending submission
--     the same way.
--   * `resolve_new_feature(discard_mine)` soft-deletes a submission via
--     `superseded_at = now(), superseded_by_id = null` — the photo rows
--     stay but their content is no longer needed.
--
-- This migration adds a `cleanup_orphan_photos()` function and (if
-- pg_cron is enabled) schedules it nightly. Manual invocation via
-- `select public.cleanup_orphan_photos();` is also supported.
--
-- The function is intentionally `security definer` and not granted to
-- `authenticated` — only `service_role` and pg_cron run it.

create or replace function public.cleanup_orphan_photos()
returns table(deleted_objects int, deleted_photo_rows int)
language plpgsql
security definer
as $$
declare
  v_deleted_objects int := 0;
  v_deleted_rows int := 0;
begin
  -- Step 1: explicit "discard" submissions (superseded_at IS NOT NULL,
  -- superseded_by_id IS NULL). Their photo rows still exist; remove the
  -- storage objects + rows together.
  with discarded as (
    select p.id as photo_id, p.storage_path
    from public.photos p
    join public.submissions s on s.id = p.submission_id
    where s.superseded_at is not null
      and s.superseded_by_id is null
      and p.storage_path is not null
  ),
  obj_delete as (
    delete from storage.objects o
    where o.bucket_id = 'photos'
      and o.name in (select storage_path from discarded)
    returning 1
  )
  select count(*) into v_deleted_objects from obj_delete;

  delete from public.photos p
  using public.submissions s
  where s.id = p.submission_id
    and s.superseded_at is not null
    and s.superseded_by_id is null;
  get diagnostics v_deleted_rows = row_count;

  -- Step 2: storage objects with no `photos.storage_path` reference at
  -- all (left behind by deleted submissions or external manual edits).
  with stranded as (
    delete from storage.objects o
    where o.bucket_id = 'photos'
      and not exists (
        select 1 from public.photos p where p.storage_path = o.name
      )
    returning 1
  )
  select v_deleted_objects + count(*)
    into v_deleted_objects
    from stranded;

  deleted_objects := v_deleted_objects;
  deleted_photo_rows := v_deleted_rows;
  return next;
end $$;

revoke all on function public.cleanup_orphan_photos() from public;
revoke all on function public.cleanup_orphan_photos() from authenticated;
-- `security definer` only sets the *runtime* identity; callers still need
-- their own EXECUTE grant. service_role does not inherit it from public,
-- so the explicit grant below is what makes manual invocations work on
-- environments without pg_cron. (pg_cron itself runs as superuser.)
grant execute on function public.cleanup_orphan_photos() to service_role;

-- Schedule nightly at 03:00 UTC if pg_cron is available. Safe to run
-- on instances without pg_cron — the do-block silently skips.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- Drop any prior schedule with this name to make the migration
    -- idempotent across re-applies.
    perform cron.unschedule('cleanup-orphan-photos')
      where exists (
        select 1 from cron.job where jobname = 'cleanup-orphan-photos'
      );
    perform cron.schedule(
      'cleanup-orphan-photos',
      '0 3 * * *',
      $cron$ select public.cleanup_orphan_photos(); $cron$
    );
  end if;
end $$;
