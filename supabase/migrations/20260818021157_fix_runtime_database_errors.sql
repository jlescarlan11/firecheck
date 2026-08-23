begin;

-- Fix two RPC failures caught by plpgsql_check on PostgreSQL 17:
-- enum input needs an explicit cast and GeoJSON must be parsed as geometry
-- before conversion to geography. The helpers also enforce membership and
-- stamp the authenticated user instead of trusting submitted_by from JSON.

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

  if not exists (
    select 1
    from public.assignment_members am
    where am.assignment_id = v_assignment_id
      and am.enumerator_id = auth.uid()
  ) then
    raise exception 'not_member' using errcode = '42501';
  end if;

  insert into public.submissions (
    id, feature_id, submitted_by, does_not_exist, remarks, override_reason,
    created_at, updated_at
  )
  values (
    (v_submission->>'id')::uuid,
    (v_submission->>'feature_id')::uuid,
    auth.uid(),
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
      (v_household->>'lebel_ng_kahinaan')::public.kahinaan_level,
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

create or replace function public.update_feature_geometry(
  p_revision_id    uuid,
  p_feature_id     uuid,
  p_prev_geojson   text,
  p_new_geojson    text,
  p_edited_at      timestamptz,
  p_override_reason text
) returns void
language plpgsql
security definer
as $$
declare
  v_current geography;
  v_prev    geography;
  v_new     geography;
begin
  if not exists (
    select 1
    from public.features f
    join public.assignment_members am
      on am.assignment_id = f.assignment_id
    where f.id = p_feature_id
      and am.enumerator_id = auth.uid()
  ) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  v_prev := st_setsrid(st_geomfromgeojson(p_prev_geojson), 4326)::geography;
  v_new  := st_setsrid(st_geomfromgeojson(p_new_geojson), 4326)::geography;

  select geometry into v_current from public.features
    where id = p_feature_id for update;

  if not st_equals(v_current::geometry, v_prev::geometry) then
    raise exception 'geometry_conflict' using errcode = 'P0001';
  end if;

  insert into public.feature_geometry_revisions
    (id, feature_id, edited_by, prev_geometry, new_geometry, edited_at, override_reason)
  values
    (p_revision_id, p_feature_id, auth.uid(), v_prev, v_new, p_edited_at, p_override_reason);

  update public.features set geometry = v_new where id = p_feature_id;
end;
$$;

-- Geometry revision rows follow the same multi-user membership policy as
-- their parent feature.
drop policy if exists fgr_enum_insert
  on public.feature_geometry_revisions;
drop policy if exists fgr_enum_select
  on public.feature_geometry_revisions;

create policy fgr_member_insert
  on public.feature_geometry_revisions
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.features f
      join public.assignment_members am
        on am.assignment_id = f.assignment_id
      where f.id = feature_geometry_revisions.feature_id
        and am.enumerator_id = (select auth.uid())
    )
  );

create policy fgr_member_select
  on public.feature_geometry_revisions
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.features f
      join public.assignment_members am
        on am.assignment_id = f.assignment_id
      where f.id = feature_geometry_revisions.feature_id
        and am.enumerator_id = (select auth.uid())
    )
  );

-- These are internal helpers called by authenticated wrapper RPCs. Keeping
-- them directly executable would bypass conflict and membership checks.
revoke execute on function public.upload_submission_bundle(jsonb)
  from public, anon, authenticated;
revoke execute on function public.upload_new_feature(jsonb)
  from public, anon, authenticated;
revoke execute on function public.attribution_values_equal(uuid, uuid, text)
  from public, anon, authenticated;

-- Read APIs are authenticated-only; RLS still enforces assignment membership.
revoke execute on function public.fetch_remote_attributions(uuid, timestamptz)
  from public, anon;
revoke execute on function public.fetch_remote_new_features(uuid, timestamptz)
  from public, anon;
grant execute on function public.fetch_remote_attributions(uuid, timestamptz)
  to authenticated;
grant execute on function public.fetch_remote_new_features(uuid, timestamptz)
  to authenticated;

-- Trigger functions are not public RPC endpoints.
revoke execute on function public.set_feature_possible_duplicate()
  from public, anon, authenticated;
revoke execute on function public.set_features_updated_at()
  from public, anon, authenticated;

-- The geometry update remains a client-facing authenticated RPC.
revoke execute on function public.update_feature_geometry(
  uuid, uuid, text, text, timestamptz, text
) from public, anon;
grant execute on function public.update_feature_geometry(
  uuid, uuid, text, text, timestamptz, text
) to authenticated;

commit;
