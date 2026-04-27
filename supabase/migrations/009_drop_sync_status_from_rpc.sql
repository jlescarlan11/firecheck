-- Phase 4a fix (Bug 7 caught during manual happy path):
-- submissions.sync_status is LOCAL-ONLY per master spec §6.
-- Migration 008 incorrectly INSERT/UPDATEd it; remove from the RPC.
create or replace function public.upload_submission_bundle(payload jsonb)
returns text
language plpgsql
security definer
as $$
declare
  v_submission jsonb := payload->'submission';
  v_feature_type text := payload->>'feature_type';
  v_building jsonb := payload->'building_attributes';
  v_road jsonb := payload->'road_attributes';
  v_household jsonb := payload->'household_survey';
  v_assignment_id uuid;
  v_closed boolean;
begin
  select a.id, a.closed_remotely into v_assignment_id, v_closed
  from public.assignments a
  join public.features f on f.assignment_id = a.id
  where f.id = (v_submission->>'feature_id')::uuid;

  if v_closed then
    raise exception 'assignment_closed' using errcode = '53300';
  end if;

  insert into public.submissions (
    id, feature_id, submitted_by, does_not_exist, remarks, override_reason,
    created_at, updated_at
  )
  values (
    (v_submission->>'id')::uuid,
    (v_submission->>'feature_id')::uuid,
    (v_submission->>'submitted_by')::uuid,
    (v_submission->>'does_not_exist')::boolean,
    v_submission->>'remarks',
    v_submission->>'override_reason',
    (v_submission->>'created_at')::timestamptz,
    (v_submission->>'updated_at')::timestamptz
  )
  on conflict (id) do update set
    does_not_exist = excluded.does_not_exist,
    remarks = excluded.remarks,
    override_reason = excluded.override_reason,
    updated_at = excluded.updated_at;

  if jsonb_typeof(v_building) = 'object' and v_feature_type = 'building' then
    insert into public.building_attributes (
      submission_id, cbms_id, building_name, ra_9514_type, storeys, material,
      cost_is_exact, cost_amount, cost_estimate_range,
      fire_fighting_facilities, fire_load
    )
    values (
      (v_building->>'submission_id')::uuid,
      v_building->>'cbms_id',
      v_building->>'building_name',
      v_building->>'ra_9514_type',
      (v_building->>'storeys')::int,
      v_building->>'material',
      coalesce((v_building->>'cost_is_exact')::boolean, false),
      (v_building->>'cost_amount')::numeric,
      v_building->>'cost_estimate_range',
      array(select jsonb_array_elements_text(coalesce(v_building->'fire_fighting_facilities', '[]'::jsonb))),
      array(select jsonb_array_elements_text(coalesce(v_building->'fire_load', '[]'::jsonb)))
    )
    on conflict (submission_id) do update set
      cbms_id = excluded.cbms_id,
      building_name = excluded.building_name,
      ra_9514_type = excluded.ra_9514_type,
      storeys = excluded.storeys,
      material = excluded.material,
      cost_is_exact = excluded.cost_is_exact,
      cost_amount = excluded.cost_amount,
      cost_estimate_range = excluded.cost_estimate_range,
      fire_fighting_facilities = excluded.fire_fighting_facilities,
      fire_load = excluded.fire_load;
  end if;

  if jsonb_typeof(v_road) = 'object' and v_feature_type = 'road' then
    insert into public.road_attributes (
      submission_id, is_bridge, road_name, width_meters,
      road_features, others_description
    )
    values (
      (v_road->>'submission_id')::uuid,
      coalesce((v_road->>'is_bridge')::boolean, false),
      v_road->>'road_name',
      (v_road->>'width_meters')::numeric,
      array(select jsonb_array_elements_text(coalesce(v_road->'road_features', '[]'::jsonb))),
      v_road->>'others_description'
    )
    on conflict (submission_id) do update set
      is_bridge = excluded.is_bridge,
      road_name = excluded.road_name,
      width_meters = excluded.width_meters,
      road_features = excluded.road_features,
      others_description = excluded.others_description;
  end if;

  if jsonb_typeof(v_household) = 'object' then
    insert into public.household_surveys (
      submission_id, construction_details, kaayusan,
      koneksyong_elektrikal, kusina, daanan_o_labasan,
      lebel_ng_kahinaan, safety_suggestions,
      homeowner_acknowledged, completed_at
    )
    values (
      (v_household->>'submission_id')::uuid,
      coalesce(v_household->'construction_details', '{}'::jsonb),
      coalesce(v_household->'kaayusan', '{}'::jsonb),
      coalesce(v_household->'koneksyong_elektrikal', '{}'::jsonb),
      coalesce(v_household->'kusina', '{}'::jsonb),
      coalesce(v_household->'daanan_o_labasan', '{}'::jsonb),
      v_household->>'lebel_ng_kahinaan',
      v_household->>'safety_suggestions',
      coalesce((v_household->>'homeowner_acknowledged')::boolean, false),
      (v_household->>'completed_at')::timestamptz
    )
    on conflict (submission_id) do update set
      construction_details = excluded.construction_details,
      kaayusan = excluded.kaayusan,
      koneksyong_elektrikal = excluded.koneksyong_elektrikal,
      kusina = excluded.kusina,
      daanan_o_labasan = excluded.daanan_o_labasan,
      lebel_ng_kahinaan = excluded.lebel_ng_kahinaan,
      safety_suggestions = excluded.safety_suggestions,
      homeowner_acknowledged = excluded.homeowner_acknowledged,
      completed_at = excluded.completed_at;
  end if;

  return 'ok';
end;
$$;

grant execute on function public.upload_submission_bundle(jsonb) to authenticated;
