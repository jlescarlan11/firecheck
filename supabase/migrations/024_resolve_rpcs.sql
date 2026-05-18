-- supabase/migrations/024_resolve_rpcs.sql
-- Resolution RPCs called after user review.
--
-- resolve_attribution(pending_id, decision):
--   decision in ('keep_theirs','force_overwrite')
--   keep_theirs    → delete pending row + children. Returns { resolved: 'keep_theirs',
--                                                            canonical_submission_id }.
--   force_overwrite→ supersede the prior canonical with the pending, audit. Returns
--                    { resolved: 'force_overwrite', canonical_submission_id: pending_id }.
--
-- resolve_new_feature(pending_id, decision):
--   decision in ('keep_both','replace_theirs','discard_mine')
--   keep_both       → just set dedup_reviewed_at. Returns { resolved: 'keep_both' }.
--   replace_theirs  → soft-delete the older feature (mark its latest submission
--                     superseded with null replacement), audit. Returns { resolved: 'replace_theirs' }.
--   discard_mine    → soft-delete the pending feature similarly, audit. Returns { resolved: 'discard_mine' }.

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
  v_actor uuid := auth.uid();
  v_prior_id uuid;
begin
  if decision not in ('keep_theirs','force_overwrite') then
    raise exception 'invalid_decision: %', decision using errcode='22023';
  end if;

  select feature_id into v_feature_id
    from public.submissions where id = pending_id;
  if v_feature_id is null then
    raise exception 'pending_not_found' using errcode='P0002';
  end if;

  -- Current canonical (anyone non-superseded other than pending).
  select id into v_prior_id
    from public.submissions
    where feature_id = v_feature_id
      and superseded_at is null
      and id <> pending_id
    order by created_at desc
    limit 1;

  if decision = 'keep_theirs' then
    -- The pending row was never canonical; deleting it is a withdraw, not an
    -- audit-worthy supersede of canonical state. No audit row written.
    delete from public.building_attributes where submission_id = pending_id;
    delete from public.road_attributes where submission_id = pending_id;
    delete from public.household_surveys where submission_id = pending_id;
    delete from public.submissions where id = pending_id;

    return jsonb_build_object('resolved','keep_theirs',
                              'canonical_submission_id', v_prior_id);
  end if;

  -- force_overwrite
  if v_prior_id is null then
    -- Nothing to supersede — treat as committed.
    return jsonb_build_object('resolved','force_overwrite',
                              'canonical_submission_id', pending_id);
  end if;

  -- Snapshot prior values BEFORE the update so the audit reflects pre-state.
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

grant execute on function public.resolve_attribution(uuid, text, text) to authenticated;


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
  v_to_soft_delete uuid;
  v_other uuid;
  v_prior jsonb;
  v_latest_sub uuid;
begin
  if decision not in ('keep_both','replace_theirs','discard_mine') then
    raise exception 'invalid_decision: %', decision using errcode='22023';
  end if;

  select possible_duplicate_of into v_dup_of
    from public.features where id = pending_id;

  if v_dup_of is null and decision <> 'keep_both' then
    raise exception 'no_duplicate_to_resolve' using errcode='22023';
  end if;

  if decision = 'keep_both' then
    -- Snapshot the pending feature's prior state before flipping dedup_reviewed_at.
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

  -- Snapshot the feature we're about to soft-delete *before* any updates touch it.
  select to_jsonb(f.*) into v_prior
    from public.features f where f.id = v_to_soft_delete;

  -- Find the latest non-superseded submission on the feature we're soft-deleting.
  select id into v_latest_sub
    from public.submissions
    where feature_id = v_to_soft_delete and superseded_at is null
    order by created_at desc limit 1;

  if v_latest_sub is not null then
    update public.submissions
      set superseded_at = now(),
          superseded_by_id = null   -- null = "discarded", not "replaced by"
      where id = v_latest_sub;
  end if;

  -- Mark both features as reviewed.
  update public.features set dedup_reviewed_at = now() where id = v_other;
  update public.features set dedup_reviewed_at = now() where id = v_to_soft_delete;

  insert into public.attribution_audit_log
    (table_name, row_id, action, performed_by, prior_snapshot, resolution_note)
    values ('features', v_to_soft_delete, 'dedup_resolve',
            v_actor, v_prior, coalesce(resolution_note, decision));

  return jsonb_build_object('resolved', decision);
end;
$$;

grant execute on function public.resolve_new_feature(uuid, text, text) to authenticated;
