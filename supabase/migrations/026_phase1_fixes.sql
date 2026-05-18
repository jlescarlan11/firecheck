-- supabase/migrations/026_phase1_fixes.sql
-- Closing fixes from Phase 1 holistic review:
--   Fix A: attribution_values_equal also compares household_surveys alongside
--          the typed child row, so a household-only delta is detected as a
--          real conflict (and not auto-collapsed to agreed_skip).
--   Fix B: resolve_attribution / resolve_new_feature gain idempotency
--          early-returns. Calling resolve_* a second time with the same
--          pending_id is now a documented no-op:
--            resolve_attribution: if pending row is gone, return
--              { resolved:'keep_theirs', canonical_submission_id:null,
--                idempotent:true }.
--              If the pending row is still present AND no other non-superseded
--              submission exists for the feature, treat as already-force-overwritten
--              and return { resolved:'force_overwrite',
--                           canonical_submission_id: pending_id,
--                           idempotent:true }.
--            resolve_new_feature: if dedup_reviewed_at IS NOT NULL on
--              pending_id, return { resolved:'already_reviewed',
--                                   idempotent:true } and let clients
--              treat that as a no-op.
--   Fix C: submit_attribution_with_conflict_check returns the full
--          { status:'conflict', pending_id, their_submission_id } shape
--          on an idempotent retry when the caller's row has since been
--          superseded by a third party, or when it is currently the
--          pending side against a different canonical. Committed rows
--          still return { status:'committed', submission_id }.
--   Fix D: All three new RPCs (022, 023, 024 × 2) gain an
--          assignment_members membership guard. Non-members raise
--          'not_member' (sqlstate 42501). Note: auth.uid() is null when
--          called from raw psql without a JWT — smoke-tests must set
--          `request.jwt.claim.sub` first.

-- ---------------------------------------------------------------------------
-- Fix A — attribution_values_equal now also considers household_surveys.
-- ---------------------------------------------------------------------------
create or replace function public.attribution_values_equal(
  a_submission_id uuid,
  b_submission_id uuid,
  v_feature_type text
)
returns boolean
language plpgsql
stable
as $$
declare
  a_dne boolean;  b_dne boolean;
  a_typed jsonb;  b_typed jsonb;
  a_household jsonb; b_household jsonb;
  typed_match boolean;
  household_match boolean;
begin
  select does_not_exist into a_dne
    from public.submissions where id = a_submission_id;
  select does_not_exist into b_dne
    from public.submissions where id = b_submission_id;

  -- "Does not exist" is a top-level attribution — must agree on its own.
  if coalesce(a_dne, false) <> coalesce(b_dne, false) then
    return false;
  end if;

  -- If both are "does not exist", child values are irrelevant.
  if coalesce(a_dne, false) = true then
    return true;
  end if;

  -- Typed child comparison (building or road).
  case v_feature_type
    when 'building' then
      select to_jsonb(ba.*) - 'submission_id' into a_typed
        from public.building_attributes ba where ba.submission_id = a_submission_id;
      select to_jsonb(ba.*) - 'submission_id' into b_typed
        from public.building_attributes ba where ba.submission_id = b_submission_id;
    when 'road' then
      select to_jsonb(ra.*) - 'submission_id' into a_typed
        from public.road_attributes ra where ra.submission_id = a_submission_id;
      select to_jsonb(ra.*) - 'submission_id' into b_typed
        from public.road_attributes ra where ra.submission_id = b_submission_id;
    else
      -- Unknown type: be conservative — treat as "not equal".
      return false;
  end case;

  -- Household survey comparison (independent of feature_type).
  select to_jsonb(hs.*) - 'submission_id' into a_household
    from public.household_surveys hs where hs.submission_id = a_submission_id;
  select to_jsonb(hs.*) - 'submission_id' into b_household
    from public.household_surveys hs where hs.submission_id = b_submission_id;

  typed_match := (a_typed is null and b_typed is null)
              or (a_typed is not distinct from b_typed);
  household_match := (a_household is null and b_household is null)
                  or (a_household is not distinct from b_household);

  return typed_match and household_match;
end;
$$;

-- ---------------------------------------------------------------------------
-- Fix C + Fix D — submit_attribution_with_conflict_check
-- ---------------------------------------------------------------------------
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
begin
  -- Closed-assignment gate (matches upload_submission_bundle).
  select a.id, a.closed_remotely into v_assignment_id, v_closed
    from public.assignments a
    join public.features f on f.assignment_id = a.id
    where f.id = v_feature_id;

  if v_closed then
    raise exception 'assignment_closed' using errcode = '53300';
  end if;

  -- Fix D: assignment-membership guard.
  if not exists (
    select 1 from public.assignment_members am
    where am.assignment_id = v_assignment_id
      and am.enumerator_id = auth.uid()
  ) then
    raise exception 'not_member' using errcode='42501';
  end if;

  -- Idempotency: same submission id already inserted?
  -- Fix C: distinguish committed vs conflict vs (superseded-later) conflict.
  if exists (select 1 from public.submissions where id = v_submission_id) then
    select superseded_at into v_existing_superseded_at
      from public.submissions where id = v_submission_id;

    if v_existing_superseded_at is null then
      -- Row is non-superseded. Check whether another non-superseded
      -- submission exists for the same feature.
      select id into v_existing_canonical
        from public.submissions
        where feature_id = v_feature_id
          and superseded_at is null
          and id <> v_submission_id
        order by created_at desc
        limit 1;

      if v_existing_canonical is null then
        -- We are currently canonical.
        return jsonb_build_object('status','committed','submission_id', v_submission_id);
      else
        -- We are the pending side against another canonical.
        return jsonb_build_object(
          'status','conflict',
          'pending_id', v_submission_id,
          'their_submission_id', v_existing_canonical
        );
      end if;
    else
      -- We were superseded later by a third party. Surface full conflict
      -- shape so the client can rerun resolution if it wants.
      select id into v_existing_canonical
        from public.submissions
        where feature_id = v_feature_id
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
        -- Concurrent supersede won — re-detect using current canonical,
        -- excluding our just-inserted row.
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

-- ---------------------------------------------------------------------------
-- Fix D — submit_new_feature_with_dedup_check (add membership guard).
-- ---------------------------------------------------------------------------
create or replace function public.submit_new_feature_with_dedup_check(payload jsonb)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_id uuid := (payload->>'id')::uuid;
  v_assignment_id uuid := (payload->>'assignment_id')::uuid;
  v_duplicate_of uuid;
begin
  -- Fix D: assignment-membership guard.
  if not exists (
    select 1 from public.assignment_members am
    where am.assignment_id = v_assignment_id
      and am.enumerator_id = auth.uid()
  ) then
    raise exception 'not_member' using errcode='42501';
  end if;

  -- Idempotency: re-derive status from existing row if already inserted.
  if exists (select 1 from public.features where id = v_id) then
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

-- ---------------------------------------------------------------------------
-- Fix B + Fix D — resolve_attribution (idempotency + membership guard).
-- ---------------------------------------------------------------------------
create or replace function public.resolve_attribution(
  pending_id uuid,
  decision text,
  resolution_note text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_feature_id uuid;
  v_assignment_id uuid;
  v_actor uuid := auth.uid();
  v_prior_id uuid;
  v_pending_superseded_at timestamptz;
  v_pending_exists boolean;
  v_other_canonical uuid;
begin
  if decision not in ('keep_theirs','force_overwrite') then
    raise exception 'invalid_decision: %', decision using errcode='22023';
  end if;

  -- Fetch the pending row state (it may have been resolved already).
  select feature_id, superseded_at into v_feature_id, v_pending_superseded_at
    from public.submissions where id = pending_id;
  v_pending_exists := (v_feature_id is not null);

  -- Fix B: idempotency early-returns.
  if not v_pending_exists then
    -- Row is gone — resolution already happened (likely keep_theirs).
    -- We don't know the original feature_id, so canonical_submission_id
    -- cannot be derived. Return a noop with null canonical id.
    return jsonb_build_object(
      'resolved','keep_theirs',
      'canonical_submission_id', null,
      'idempotent', true
    );
  end if;

  -- Fix D: membership guard (derive assignment via the pending row's feature).
  select f.assignment_id into v_assignment_id
    from public.features f where f.id = v_feature_id;

  if not exists (
    select 1 from public.assignment_members am
    where am.assignment_id = v_assignment_id
      and am.enumerator_id = auth.uid()
  ) then
    raise exception 'not_member' using errcode='42501';
  end if;

  -- Pending row exists. Look for another non-superseded canonical.
  select id into v_other_canonical
    from public.submissions
    where feature_id = v_feature_id
      and superseded_at is null
      and id <> pending_id
    order by created_at desc
    limit 1;

  -- Fix B: if pending is still non-superseded AND no other canonical
  -- exists for this feature, treat this as an already-force-overwritten
  -- state and return idempotently. (Per spec: structural check, no
  -- audit-log lookup.)
  if v_pending_superseded_at is null and v_other_canonical is null then
    return jsonb_build_object(
      'resolved','force_overwrite',
      'canonical_submission_id', pending_id,
      'idempotent', true
    );
  end if;

  v_prior_id := v_other_canonical;

  if decision = 'keep_theirs' then
    delete from public.building_attributes where submission_id = pending_id;
    delete from public.road_attributes where submission_id = pending_id;
    delete from public.household_surveys where submission_id = pending_id;
    delete from public.submissions where id = pending_id;

    return jsonb_build_object('resolved','keep_theirs',
                              'canonical_submission_id', v_prior_id);
  end if;

  -- force_overwrite — there is a prior canonical to supersede.
  if v_prior_id is null then
    -- Defensive: structural early-return above should have handled this,
    -- but keep a fallback that mirrors original 024 behavior.
    return jsonb_build_object('resolved','force_overwrite',
                              'canonical_submission_id', pending_id);
  end if;

  declare v_prior_snapshot jsonb;
  begin
    select to_jsonb(s.*) into v_prior_snapshot
      from public.submissions s where s.id = v_prior_id;

    update public.submissions
      set superseded_at = now(),
          superseded_by_id = pending_id
      where id = v_prior_id
        and superseded_at is null;
    if not found then
      raise exception 'concurrent_supersede_lost_race' using errcode='40001';
    end if;

    insert into public.attribution_audit_log
      (table_name, row_id, action, performed_by, prior_snapshot, resolution_note)
    values ('submissions', v_prior_id, 'force_overwrite',
            v_actor, v_prior_snapshot, resolution_note);
  end;

  return jsonb_build_object('resolved','force_overwrite',
                            'canonical_submission_id', pending_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- Fix B + Fix D — resolve_new_feature (idempotency + membership guard).
-- ---------------------------------------------------------------------------
create or replace function public.resolve_new_feature(
  pending_id uuid,
  decision text,
  resolution_note text default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_dup_of uuid;
  v_actor uuid := auth.uid();
  v_assignment_id uuid;
  v_reviewed_at timestamptz;
  v_to_soft_delete uuid;
  v_other uuid;
  v_prior jsonb;
  v_latest_sub uuid;
begin
  if decision not in ('keep_both','replace_theirs','discard_mine') then
    raise exception 'invalid_decision: %', decision using errcode='22023';
  end if;

  -- Fix D: derive assignment from the pending feature itself.
  select assignment_id, dedup_reviewed_at, possible_duplicate_of
    into v_assignment_id, v_reviewed_at, v_dup_of
    from public.features where id = pending_id;

  if v_assignment_id is null then
    -- Pending feature doesn't even exist — surface as not_found.
    raise exception 'pending_not_found' using errcode='P0002';
  end if;

  if not exists (
    select 1 from public.assignment_members am
    where am.assignment_id = v_assignment_id
      and am.enumerator_id = auth.uid()
  ) then
    raise exception 'not_member' using errcode='42501';
  end if;

  -- Fix B: idempotency early-return.
  if v_reviewed_at is not null then
    return jsonb_build_object(
      'resolved','already_reviewed',
      'idempotent', true
    );
  end if;

  if v_dup_of is null and decision <> 'keep_both' then
    raise exception 'no_duplicate_to_resolve' using errcode='22023';
  end if;

  if decision = 'keep_both' then
    select to_jsonb(f.*) into v_prior
      from public.features f where f.id = pending_id;
    update public.features set dedup_reviewed_at = now() where id = pending_id;
    insert into public.attribution_audit_log
      (table_name, row_id, action, performed_by, prior_snapshot, resolution_note)
    values ('features', pending_id, 'dedup_resolve',
            v_actor, v_prior, coalesce(resolution_note,'keep_both'));
    return jsonb_build_object('resolved','keep_both');
  end if;

  if decision = 'replace_theirs' then
    v_to_soft_delete := v_dup_of;
    v_other := pending_id;
  else  -- discard_mine
    v_to_soft_delete := pending_id;
    v_other := v_dup_of;
  end if;

  select to_jsonb(f.*) into v_prior
    from public.features f where f.id = v_to_soft_delete;

  select id into v_latest_sub
    from public.submissions
    where feature_id = v_to_soft_delete and superseded_at is null
    order by created_at desc limit 1;

  if v_latest_sub is not null then
    update public.submissions
      set superseded_at = now(),
          superseded_by_id = null
      where id = v_latest_sub;
  end if;

  update public.features set dedup_reviewed_at = now() where id = v_other;
  update public.features set dedup_reviewed_at = now() where id = v_to_soft_delete;

  insert into public.attribution_audit_log
    (table_name, row_id, action, performed_by, prior_snapshot, resolution_note)
    values ('features', v_to_soft_delete, 'dedup_resolve',
            v_actor, v_prior, coalesce(resolution_note, decision));

  return jsonb_build_object('resolved', decision);
end;
$$;

-- (Grants survive create-or-replace; signatures unchanged.)
