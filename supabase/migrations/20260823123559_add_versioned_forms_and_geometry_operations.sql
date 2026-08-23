-- Versioned form contracts and atomic offline geometry operations.

create table public.form_definitions (
  version text primary key,
  definition jsonb not null,
  published_at timestamptz not null default now(),
  is_active boolean not null default false,
  constraint definition_version_matches check (definition->>'version' = version)
);

insert into public.form_definitions (version, definition, is_active)
values ('legacy-v1', '{"version":"legacy-v1","name":"Legacy","visibilityRules":[],"constraints":[]}', true);

alter table public.form_definitions enable row level security;
create policy form_definitions_authenticated_read on public.form_definitions
  for select to authenticated using (auth.uid() is not null);
revoke all on table public.form_definitions from anon, authenticated;
grant select on table public.form_definitions to authenticated;

alter table public.submissions
  add column form_version text not null default 'legacy-v1'
  references public.form_definitions(version);

alter table public.features
  add column split_from_id uuid references public.features(id),
  add column merged_into_id uuid references public.features(id);

alter table public.feature_geometry_revisions
  add column operation text not null default 'reshape'
    check (operation in ('reshape', 'split', 'merge')),
  add column related_feature_id uuid,
  add column related_geometry geography(Geometry, 4326);

create or replace function public.form_answer_value(payload jsonb, field_name text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case field_name
    when 'building.storeys' then payload#>'{building_attributes,storeys}'
    when 'building.costAmount' then payload#>'{building_attributes,cost_amount}'
    when 'building.buildingName' then payload#>'{building_attributes,building_name}'
    when 'road.widthMeters' then payload#>'{road_attributes,width_meters}'
    when 'road.roadName' then payload#>'{road_attributes,road_name}'
    when 'submission.doesNotExist' then payload#>'{submission,does_not_exist}'
    else null
  end
$$;
revoke all on function public.form_answer_value(jsonb, text) from public, anon, authenticated;

create or replace function public.validate_form_constraints(payload jsonb, definition jsonb)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  rule jsonb;
  value jsonb;
  numeric_value numeric;
begin
  for rule in select * from jsonb_array_elements(coalesce(definition->'constraints', '[]'::jsonb)) loop
    value := public.form_answer_value(payload, rule->>'field');
    if coalesce((rule->>'required')::boolean, false)
       and (value is null or value = 'null'::jsonb or value = '""'::jsonb or value = '[]'::jsonb) then
      raise exception 'form_constraint_required:%', rule->>'field' using errcode = '23514';
    end if;
    if value is not null and jsonb_typeof(value) = 'number' then
      numeric_value := (value#>>'{}')::numeric;
      if rule ? 'min' and numeric_value < (rule->>'min')::numeric then
        raise exception 'form_constraint_min:%', rule->>'field' using errcode = '23514';
      end if;
      if rule ? 'max' and numeric_value > (rule->>'max')::numeric then
        raise exception 'form_constraint_max:%', rule->>'field' using errcode = '23514';
      end if;
      if coalesce((rule->>'maxCurrentYear')::boolean, false)
         and numeric_value > extract(year from current_date) then
        raise exception 'form_constraint_max_current_year:%', rule->>'field' using errcode = '23514';
      end if;
    end if;
  end loop;
end
$$;
revoke all on function public.validate_form_constraints(jsonb, jsonb) from public, anon, authenticated;

-- Preserve the mature bundle writer behind a validating, version-aware wrapper.
alter function public.upload_submission_bundle(jsonb)
  rename to upload_submission_bundle_unversioned;
revoke all on function public.upload_submission_bundle_unversioned(jsonb) from public, anon, authenticated;

create function public.upload_submission_bundle(payload jsonb)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  version text := coalesce(nullif(payload->'submission'->>'form_version', ''), 'legacy-v1');
  definition jsonb;
  result text;
begin
  select fd.definition into definition
  from public.form_definitions fd where fd.version = version;
  if definition is null then
    raise exception 'unknown_form_version:%', version using errcode = '23503';
  end if;
  perform public.validate_form_constraints(payload, definition);
  result := public.upload_submission_bundle_unversioned(payload);
  update public.submissions
    set form_version = version
    where id = (payload->'submission'->>'id')::uuid;
  return result;
end
$$;
revoke all on function public.upload_submission_bundle(jsonb) from public, anon;
grant execute on function public.upload_submission_bundle(jsonb) to authenticated;

create or replace function public.update_feature_geometry(
  p_revision_id uuid,
  p_feature_id uuid,
  p_prev_geojson text,
  p_new_geojson text,
  p_edited_at timestamptz,
  p_override_reason text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_feature public.features%rowtype;
  previous_geometry geography;
  new_geometry geography;
begin
  select * into current_feature from public.features
    where id = p_feature_id for update;
  if not found or not exists (
    select 1 from public.assignment_members am
    where am.assignment_id = current_feature.assignment_id
      and am.enumerator_id = auth.uid()
  ) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if exists (select 1 from public.assignments a
             where a.id = current_feature.assignment_id
               and (a.status = 'submitted' or a.closed_remotely))
     or exists (select 1 from public.submissions s
                where s.feature_id = p_feature_id and s.superseded_at is null) then
    raise exception 'feature_finalized' using errcode = '55000';
  end if;
  if exists (select 1 from public.feature_geometry_revisions where id = p_revision_id) then
    return;
  end if;
  previous_geometry := st_geogfromgeojson(p_prev_geojson);
  new_geometry := st_geogfromgeojson(p_new_geojson);
  if not st_isvalid(new_geometry::geometry)
     or not exists (
       select 1 from public.assignments a
       where a.id = current_feature.assignment_id
         and st_coveredby(new_geometry::geometry, a.boundary_polygon::geometry)
     ) then
    raise exception 'invalid_or_outside_boundary' using errcode = '22023';
  end if;
  if not st_equals(current_feature.geometry::geometry, previous_geometry::geometry) then
    raise exception 'geometry_conflict' using errcode = 'P0001';
  end if;
  update public.features set geometry = new_geometry where id = p_feature_id;
  insert into public.feature_geometry_revisions
    (id, feature_id, edited_by, prev_geometry, new_geometry, edited_at,
     override_reason, operation)
  values
    (p_revision_id, p_feature_id, auth.uid(), previous_geometry, new_geometry,
     p_edited_at, p_override_reason, 'reshape');
end
$$;
revoke all on function public.update_feature_geometry(
  uuid, uuid, text, text, timestamptz, text
) from public, anon;
grant execute on function public.update_feature_geometry(
  uuid, uuid, text, text, timestamptz, text
) to authenticated;

create or replace function public.apply_feature_geometry_operation(
  p_revision_id uuid,
  p_feature_id uuid,
  p_prev_geojson text,
  p_new_geojson text,
  p_edited_at timestamptz,
  p_override_reason text,
  p_operation text,
  p_related_feature_id uuid,
  p_related_geojson text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_feature public.features%rowtype;
  related_feature public.features%rowtype;
  previous_geometry geography;
  new_geometry geography;
  related_geometry geography;
begin
  if p_operation not in ('split', 'merge') or p_related_feature_id is null then
    raise exception 'invalid_geometry_operation' using errcode = '22023';
  end if;

  select * into current_feature from public.features
    where id = p_feature_id for update;
  if not found or not exists (
    select 1 from public.assignment_members am
    where am.assignment_id = current_feature.assignment_id
      and am.enumerator_id = auth.uid()
  ) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if exists (select 1 from public.assignments a
             where a.id = current_feature.assignment_id
               and (a.status = 'submitted' or a.closed_remotely))
     or exists (select 1 from public.submissions s
                where s.feature_id = p_feature_id and s.superseded_at is null) then
    raise exception 'feature_finalized' using errcode = '55000';
  end if;

  -- Authorized idempotency check, after membership has been established.
  if exists (select 1 from public.feature_geometry_revisions where id = p_revision_id) then
    return;
  end if;

  previous_geometry := st_geogfromgeojson(p_prev_geojson);
  new_geometry := st_geogfromgeojson(p_new_geojson);
  related_geometry := st_geogfromgeojson(p_related_geojson);
  if not st_isvalid(new_geometry::geometry)
     or not st_isvalid(related_geometry::geometry) then
    raise exception 'invalid_geometry' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.assignments a
    where a.id = current_feature.assignment_id
      and st_coveredby(new_geometry::geometry, a.boundary_polygon::geometry)
      and st_coveredby(related_geometry::geometry, a.boundary_polygon::geometry)
  ) then
    raise exception 'outside_assignment_boundary' using errcode = '22023';
  end if;
  if not st_equals(current_feature.geometry::geometry, previous_geometry::geometry) then
    raise exception 'geometry_conflict' using errcode = 'P0001';
  end if;

  if p_operation = 'split' then
    if current_feature.feature_type <> 'building' then
      raise exception 'split_requires_polygon' using errcode = '22023';
    end if;
    insert into public.features
      (id, assignment_id, feature_type, geometry, is_new, split_from_id)
    values
      (p_related_feature_id, current_feature.assignment_id,
       current_feature.feature_type, related_geometry, true, p_feature_id);
  else
    select * into related_feature from public.features
      where id = p_related_feature_id for update;
    if not found or related_feature.assignment_id <> current_feature.assignment_id
       or related_feature.feature_type <> current_feature.feature_type
       or related_feature.merged_into_id is not null
       or not st_equals(related_feature.geometry::geometry, related_geometry::geometry) then
      raise exception 'geometry_conflict' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.submissions s
               where s.feature_id = p_related_feature_id and s.superseded_at is null) then
      raise exception 'feature_finalized' using errcode = '55000';
    end if;
    update public.features set merged_into_id = p_feature_id
      where id = p_related_feature_id;
  end if;

  update public.features set geometry = new_geometry where id = p_feature_id;
  insert into public.feature_geometry_revisions
    (id, feature_id, edited_by, prev_geometry, new_geometry, edited_at,
     override_reason, operation, related_feature_id, related_geometry)
  values
    (p_revision_id, p_feature_id, auth.uid(), previous_geometry, new_geometry,
     p_edited_at, p_override_reason, p_operation, p_related_feature_id,
     related_geometry);
end
$$;
revoke all on function public.apply_feature_geometry_operation(
  uuid, uuid, text, text, timestamptz, text, text, uuid, text
) from public, anon;
grant execute on function public.apply_feature_geometry_operation(
  uuid, uuid, text, text, timestamptz, text, text, uuid, text
) to authenticated;
