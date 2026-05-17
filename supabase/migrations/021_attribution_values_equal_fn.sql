-- supabase/migrations/021_attribution_values_equal_fn.sql
-- Returns true when two submissions carry semantically identical
-- attribute values (same does_not_exist, same typed child row).
-- Used by submit_attribution_with_conflict_check to detect agreements.

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
  a_remarks text; b_remarks text;
  a_jsonb jsonb;  b_jsonb jsonb;
begin
  select does_not_exist, remarks into a_dne, a_remarks
    from public.submissions where id = a_submission_id;
  select does_not_exist, remarks into b_dne, b_remarks
    from public.submissions where id = b_submission_id;

  -- "Does not exist" is a top-level attribution — must agree on its own.
  if coalesce(a_dne, false) <> coalesce(b_dne, false) then
    return false;
  end if;

  -- If either is "does not exist", child values are irrelevant.
  if coalesce(a_dne, false) = true then
    return true;
  end if;

  -- Compare typed child rows by feature type.
  case v_feature_type
    when 'building' then
      select to_jsonb(ba.*) - 'submission_id' into a_jsonb
        from public.building_attributes ba where ba.submission_id = a_submission_id;
      select to_jsonb(ba.*) - 'submission_id' into b_jsonb
        from public.building_attributes ba where ba.submission_id = b_submission_id;
    when 'road' then
      select to_jsonb(ra.*) - 'submission_id' into a_jsonb
        from public.road_attributes ra where ra.submission_id = a_submission_id;
      select to_jsonb(ra.*) - 'submission_id' into b_jsonb
        from public.road_attributes ra where ra.submission_id = b_submission_id;
    else
      -- Unknown type: be conservative — treat as "not equal" so conflict surfaces.
      return false;
  end case;

  -- Both null = both have no typed row = equal.
  if a_jsonb is null and b_jsonb is null then
    return true;
  end if;

  return a_jsonb is not distinct from b_jsonb;
end;
$$;

-- Read-only helper; callable by RPCs.
grant execute on function public.attribution_values_equal(uuid, uuid, text) to authenticated;
