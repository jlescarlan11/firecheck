-- Phase 4a fixes (caught during manual happy path):
--
-- (a) upload_new_feature RPC: features.feature_type is an ENUM, not text;
--     cast (payload->>'feature_type')::feature_type before insert.
--
-- (b) upload_submission_bundle RPC: change conditionals from
--     "v_X is not null" to "jsonb_typeof(v_X) = 'object'" — the IS NOT NULL
--     check returns true for JSON null literals, causing inserts with null
--     submission_id when the client sends `{"household_survey": null}`.
--
-- (c) Seed ra_9514_types lookup table — the FK from
--     building_attributes.ra_9514_type was failing because the table was
--     empty. Phase 0 only seeded the local Drift table; this mirrors it
--     to remote.

-- ---- (a) ----
create or replace function public.upload_new_feature(payload jsonb)
returns text
language plpgsql
security definer
as $$
declare
  v_id uuid := (payload->>'id')::uuid;
  v_assignment_id uuid := (payload->>'assignment_id')::uuid;
  v_feature_type feature_type :=
    ((payload->>'feature_type')::feature_type);
  v_geom_geojson text := payload->>'geometry_geojson';
  v_is_new boolean := coalesce((payload->>'is_new')::boolean, true);
  v_created_at timestamptz := coalesce(
    (payload->>'created_at')::timestamptz, now()
  );
begin
  insert into public.features (
    id, assignment_id, feature_type, geometry, is_new, created_at
  )
  values (
    v_id,
    v_assignment_id,
    v_feature_type,
    ST_GeomFromGeoJSON(v_geom_geojson),
    v_is_new,
    v_created_at
  )
  on conflict (id) do update set
    feature_type = excluded.feature_type,
    geometry = excluded.geometry,
    is_new = excluded.is_new;

  return 'ok';
end;
$$;

grant execute on function public.upload_new_feature(jsonb) to authenticated;

-- ---- (b) ----
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
    sync_status, created_at, updated_at
  )
  values (
    (v_submission->>'id')::uuid,
    (v_submission->>'feature_id')::uuid,
    (v_submission->>'submitted_by')::uuid,
    (v_submission->>'does_not_exist')::boolean,
    v_submission->>'remarks',
    v_submission->>'override_reason',
    'uploaded',
    (v_submission->>'created_at')::timestamptz,
    (v_submission->>'updated_at')::timestamptz
  )
  on conflict (id) do update set
    does_not_exist = excluded.does_not_exist,
    remarks = excluded.remarks,
    override_reason = excluded.override_reason,
    sync_status = 'uploaded',
    updated_at = excluded.updated_at;

  -- jsonb_typeof check rejects both SQL NULL and JSON null literal.
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

-- ---- (c) Seed ra_9514_types ----
insert into public.ra_9514_types (code, label_en, label_tl) values
  ('A', 'Group A — Residential', 'Pangkat A — Tirahan'),
  ('B', 'Group B — Residential, Hotel and Apartment', 'Pangkat B — Tirahan, Hotel at Apartment'),
  ('C', 'Group C — Education and Recreation', 'Pangkat C — Edukasyon at Libangan'),
  ('D', 'Group D — Institutional', 'Pangkat D — Institusyonal'),
  ('E', 'Group E — Business and Mercantile', 'Pangkat E — Negosyo at Pangkalakal'),
  ('F', 'Group F — Industrial', 'Pangkat F — Industriyal'),
  ('G', 'Group G — Storage and Hazardous', 'Pangkat G — Imbakan at Mapanganib'),
  ('H', 'Group H — Assembly Other Than Group I', 'Pangkat H — Pagtitipon Bukod sa Pangkat I'),
  ('I', 'Group I — Assembly OK Less Than 1000', 'Pangkat I — Pagtitipon na Mababa sa 1000'),
  ('J', 'Group J — Special Structures', 'Pangkat J — Espesyal na Istraktura')
on conflict (code) do update set
  label_en = excluded.label_en,
  label_tl = excluded.label_tl;
