-- supabase/migrations/023_submit_new_feature_dedup.sql
-- Wraps upload_new_feature with dedup awareness. The proximity trigger
-- (migration 019) populates features.possible_duplicate_of on insert.
-- This RPC inspects that column and returns the appropriate response.
--
-- Payload: same as upload_new_feature.
--
-- Result JSON:
--   { status: 'committed',     feature_id }
--   { status: 'dedup_pending', pending_id, possible_duplicate_of }

create or replace function public.submit_new_feature_with_dedup_check(payload jsonb)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_id uuid := (payload->>'id')::uuid;
  v_duplicate_of uuid;
begin
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

grant execute on function public.submit_new_feature_with_dedup_check(jsonb) to authenticated;
