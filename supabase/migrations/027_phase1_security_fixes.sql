-- supabase/migrations/027_phase1_security_fixes.sql
-- Phase 1 security fixes from PR #54 review:
--
--   P1: submit_attribution_with_conflict_check — the idempotency branch
--       returned status keyed on payload-supplied submission_id without
--       verifying the stored row actually belongs to an assignment the
--       caller is a member of. A member of assignment A could probe any
--       submission UUID from assignment B and infer its existence and
--       superseded state. Fix: when the idempotency branch fires, re-
--       derive assignment_id from the *stored* submission's real
--       feature_id and re-check membership against that.
--
--   P2: submit_new_feature_with_dedup_check — same shape. Idempotency
--       branch returned status (committed / dedup_pending +
--       possible_duplicate_of) for any feature UUID without verifying
--       the stored feature's assignment_id matched the caller's
--       membership. Fix: re-derive auth from the stored feature's real
--       assignment_id and re-check membership before responding.
--
-- Both fixes only apply to the *idempotency* (early-return) path. The
-- normal path's membership guard against payload-derived assignment_id
-- is still correct: any newly-inserted row's assignment_id is what the
-- caller claimed, and the caller must be a member of that assignment.

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
  v_existing_superseded_at timestamptz;
  v_existing_canonical uuid;
  v_existing_feature_id uuid;
  v_existing_assignment_id uuid;
begin
  -- P1 fix: if the submission_id already exists, authorize off the
  -- *stored* row's real feature_id before returning anything. This
  -- prevents probing existence/status of submissions in assignments
  -- the caller is not a member of.
  if exists (select 1 from public.submissions where id = v_submission_id) then
    select s.feature_id, f.assignment_id, s.superseded_at
      into v_existing_feature_id, v_existing_assignment_id,
           v_existing_superseded_at
      from public.submissions s
      join public.features f on f.id = s.feature_id
      where s.id = v_submission_id;

    if not exists (
      select 1 from public.assignment_members am
      where am.assignment_id = v_existing_assignment_id
        and am.enumerator_id = auth.uid()
    ) then
      raise exception 'not_member' using errcode='42501';
    end if;

    if v_existing_superseded_at is null then
      select id into v_existing_canonical
        from public.submissions
        where feature_id = v_existing_feature_id
          and superseded_at is null
          and id <> v_submission_id
        order by created_at desc
        limit 1;

      if v_existing_canonical is null then
        return jsonb_build_object('status','committed','submission_id', v_submission_id);
      else
        return jsonb_build_object(
          'status','conflict',
          'pending_id', v_submission_id,
          'their_submission_id', v_existing_canonical
        );
      end if;
    else
      select id into v_existing_canonical
        from public.submissions
        where feature_id = v_existing_feature_id
          and superseded_at is null
        order by created_at desc
        limit 1;

      return jsonb_build_object(
        'status','conflict',
        'pending_id', v_submission_id,
        'their_submission_id', v_existing_canonical
      );
    end if;
  end if;

  -- Closed-assignment gate (matches upload_submission_bundle).
  select a.id, a.closed_remotely into v_assignment_id, v_closed
    from public.assignments a
    join public.features f on f.assignment_id = a.id
    where f.id = v_feature_id;

  if v_closed then
    raise exception 'assignment_closed' using errcode = '53300';
  end if;

  -- Fix D: assignment-membership guard for the non-idempotent path.
  if not exists (
    select 1 from public.assignment_members am
    where am.assignment_id = v_assignment_id
      and am.enumerator_id = auth.uid()
  ) then
    raise exception 'not_member' using errcode='42501';
  end if;

  -- Identify the current canonical row, if any, for this feature.
  select id into v_current_id
    from public.submissions
    where feature_id = v_feature_id and superseded_at is null
    order by created_at desc
    limit 1;

  -- Case A: no prior canonical → straight insert.
  if v_current_id is null then
    perform public.upload_submission_bundle(payload);
    return jsonb_build_object('status','committed','submission_id', v_submission_id);
  end if;

  -- Case B: explicit override of the version the client knew about.
  if v_base_version is not null and v_base_version = v_current_id then
    declare v_prior_snapshot jsonb;
    begin
      select to_jsonb(s.*) into v_prior_snapshot
        from public.submissions s where s.id = v_current_id;

      perform public.upload_submission_bundle(payload);

      update public.submissions
        set superseded_at = now(),
            superseded_by_id = v_submission_id
        where id = v_current_id
          and superseded_at is null;

      if found then
        insert into public.attribution_audit_log
          (table_name, row_id, action, performed_by, prior_snapshot)
        values ('submissions', v_current_id, 'supersede',
                (v_submission->>'submitted_by')::uuid,
                v_prior_snapshot);
        return jsonb_build_object('status','committed','submission_id', v_submission_id);
      else
        select id into v_current_id
          from public.submissions
          where feature_id = v_feature_id
            and superseded_at is null
            and id <> v_submission_id
          order by created_at desc
          limit 1;
      end if;
    end;
  end if;

  -- Case C: insert the pending bundle so we can compare typed values.
  perform public.upload_submission_bundle(payload);

  if v_current_id is null then
    return jsonb_build_object('status','committed','submission_id', v_submission_id);
  end if;

  v_equal := public.attribution_values_equal(v_current_id, v_submission_id, v_feature_type);

  if v_equal then
    delete from public.building_attributes where submission_id = v_submission_id;
    delete from public.road_attributes where submission_id = v_submission_id;
    delete from public.household_surveys where submission_id = v_submission_id;
    delete from public.submissions where id = v_submission_id;
    return jsonb_build_object('status','agreed_skip','submission_id', v_current_id);
  end if;

  return jsonb_build_object(
    'status','conflict',
    'pending_id', v_submission_id,
    'their_submission_id', v_current_id
  );
end;
$$;


create or replace function public.submit_new_feature_with_dedup_check(payload jsonb)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_id uuid := (payload->>'id')::uuid;
  v_payload_assignment_id uuid := (payload->>'assignment_id')::uuid;
  v_existing_assignment_id uuid;
  v_duplicate_of uuid;
begin
  -- P2 fix: if the feature_id already exists, authorize off the
  -- *stored* row's real assignment_id before returning anything. This
  -- prevents probing existence/dedup-state of features in assignments
  -- the caller is not a member of.
  if exists (select 1 from public.features where id = v_id) then
    select assignment_id, possible_duplicate_of
      into v_existing_assignment_id, v_duplicate_of
      from public.features where id = v_id;

    if not exists (
      select 1 from public.assignment_members am
      where am.assignment_id = v_existing_assignment_id
        and am.enumerator_id = auth.uid()
    ) then
      raise exception 'not_member' using errcode='42501';
    end if;

    if v_duplicate_of is null then
      return jsonb_build_object('status','committed','feature_id', v_id);
    else
      return jsonb_build_object(
        'status','dedup_pending',
        'pending_id', v_id,
        'possible_duplicate_of', v_duplicate_of
      );
    end if;
  end if;

  -- Non-idempotent path: authorize off the payload's assignment_id
  -- (which is what will be written to the new feature row).
  if not exists (
    select 1 from public.assignment_members am
    where am.assignment_id = v_payload_assignment_id
      and am.enumerator_id = auth.uid()
  ) then
    raise exception 'not_member' using errcode='42501';
  end if;

  perform public.upload_new_feature(payload);

  select possible_duplicate_of into v_duplicate_of
    from public.features where id = v_id;

  if v_duplicate_of is null then
    return jsonb_build_object('status','committed','feature_id', v_id);
  else
    return jsonb_build_object(
      'status','dedup_pending',
      'pending_id', v_id,
      'possible_duplicate_of', v_duplicate_of
    );
  end if;
end;
$$;
