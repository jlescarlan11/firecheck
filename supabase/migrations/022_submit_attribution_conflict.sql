-- supabase/migrations/022_submit_attribution_conflict.sql
-- Conflict-aware wrapper around upload_submission_bundle.
-- Payload shape is the same as upload_submission_bundle's, plus an
-- optional 'base_version_id' field that names the canonical submission
-- the client knew about when composing this upload.
--
-- Result JSON:
--   { status: 'committed',    submission_id }
--   { status: 'agreed_skip',  submission_id }  -- existing canonical is identical, no new row
--   { status: 'conflict',     pending_id, their_submission_id }
--
-- Pending rows: a 'conflict' result inserts the new submission rows but
-- leaves the prior canonical un-superseded. resolve_attribution then
-- either supersedes the prior (force_overwrite) or deletes the pending
-- (keep_theirs).

create or replace function public.submit_attribution_with_conflict_check(payload jsonb)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_submission jsonb := payload->'submission';
  v_feature_type text := payload->>'feature_type';
  v_base_version uuid := nullif(payload->>'base_version_id','')::uuid;
  v_submission_id uuid := (v_submission->>'id')::uuid;
  v_feature_id uuid := (v_submission->>'feature_id')::uuid;
  v_assignment_id uuid;
  v_closed boolean;
  v_current_id uuid;
  v_equal boolean;
begin
  -- Closed-assignment gate (matches upload_submission_bundle).
  select a.id, a.closed_remotely into v_assignment_id, v_closed
    from public.assignments a
    join public.features f on f.assignment_id = a.id
    where f.id = v_feature_id;

  if v_closed then
    raise exception 'assignment_closed' using errcode = '53300';
  end if;

  -- Idempotency: same submission id already inserted? Return its prior result.
  if exists (select 1 from public.submissions where id = v_submission_id) then
    -- Re-derive status. If superseded_by_id refs another row, this row is
    -- the loser. If it has superseded_at = null, it's canonical.
    return jsonb_build_object(
      'status', case
        when (select superseded_at is null from public.submissions where id = v_submission_id) then 'committed'
        else 'conflict'
      end,
      'submission_id', v_submission_id
    );
  end if;

  -- Identify the current canonical row, if any, for this feature.
  select id into v_current_id
    from public.submissions
    where feature_id = v_feature_id and superseded_at is null
    order by created_at desc
    limit 1;

  -- Case A: no prior canonical → straight insert via the existing bundle RPC.
  if v_current_id is null then
    perform public.upload_submission_bundle(payload);
    return jsonb_build_object('status','committed','submission_id', v_submission_id);
  end if;

  -- Case B: explicit override of the version the client knew about.
  if v_base_version is not null and v_base_version = v_current_id then
    -- Capture prior snapshot BEFORE we update v_current_id.
    declare v_prior_snapshot jsonb;
    begin
      select to_jsonb(s.*) into v_prior_snapshot
        from public.submissions s where s.id = v_current_id;

      perform public.upload_submission_bundle(payload);

      update public.submissions
        set superseded_at = now(),
            superseded_by_id = v_submission_id
        where id = v_current_id
          and superseded_at is null;  -- optimistic lock

      if found then
        insert into public.attribution_audit_log
          (table_name, row_id, action, performed_by, prior_snapshot)
        values ('submissions', v_current_id, 'supersede',
                (v_submission->>'submitted_by')::uuid,
                v_prior_snapshot);
        return jsonb_build_object('status','committed','submission_id', v_submission_id);
      else
        -- Concurrent supersede won — re-detect using the *current* canonical,
        -- excluding our just-inserted row so we don't compare against ourselves.
        select id into v_current_id
          from public.submissions
          where feature_id = v_feature_id
            and superseded_at is null
            and id <> v_submission_id
          order by created_at desc
          limit 1;
        -- fallthrough to value-comparison branch
      end if;
    end;
  end if;

  -- Case C: insert the pending bundle so we can compare typed values.
  -- (Idempotent if Case B already inserted via on-conflict upsert.)
  perform public.upload_submission_bundle(payload);

  -- If after a Case B race the canonical disappeared, we are now canonical.
  if v_current_id is null then
    return jsonb_build_object('status','committed','submission_id', v_submission_id);
  end if;

  -- Compare against current canonical.
  v_equal := public.attribution_values_equal(v_current_id, v_submission_id, v_feature_type);

  if v_equal then
    -- Agreement: drop the pending we just inserted and keep canonical as-is.
    delete from public.building_attributes where submission_id = v_submission_id;
    delete from public.road_attributes where submission_id = v_submission_id;
    delete from public.household_surveys where submission_id = v_submission_id;
    delete from public.submissions where id = v_submission_id;
    return jsonb_build_object('status','agreed_skip','submission_id', v_current_id);
  end if;

  -- Real conflict: leave pending row in place, do NOT supersede current.
  return jsonb_build_object(
    'status','conflict',
    'pending_id', v_submission_id,
    'their_submission_id', v_current_id
  );
end;
$$;

grant execute on function public.submit_attribution_with_conflict_check(jsonb) to authenticated;
