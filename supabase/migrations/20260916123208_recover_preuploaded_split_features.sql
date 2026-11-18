-- Recover legacy split ordering without duplicating features or losing child surveys.
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
set search_path = public, extensions, pg_temp
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
  -- A lost response can be retried after the feature was finalized. Match
  -- the stored operation, never accept a reused UUID with different geometry.
  if exists(select 1 from public.feature_geometry_revisions where id=p_revision_id) then
    if not exists(select 1 from public.feature_geometry_revisions r where r.id=p_revision_id
      and r.feature_id=p_feature_id and r.edited_by=auth.uid()
      and r.operation=p_operation and r.related_feature_id is not distinct from p_related_feature_id
      and st_equals(r.related_geometry::geometry,st_setsrid(st_geomfromgeojson(p_related_geojson),4326))
      and st_equals(r.new_geometry::geometry,st_setsrid(st_geomfromgeojson(p_new_geojson),4326))) then
      raise exception 'geometry_operation_id_reused' using errcode='22023';
    end if;
    return;
  end if;
  if exists (select 1 from public.assignments a
             where a.id = current_feature.assignment_id
               and (a.status = 'submitted' or a.closed_remotely))
     or exists (select 1 from public.submissions s
                where s.feature_id = p_feature_id and s.superseded_at is null) then
    raise exception 'feature_finalized' using errcode = '55000';
  end if;

  -- Authorized idempotency check, after membership has been established.

  previous_geometry := st_setsrid(st_geomfromgeojson(p_prev_geojson),4326)::geography;
  new_geometry := st_setsrid(st_geomfromgeojson(p_new_geojson),4326)::geography;
  related_geometry := st_setsrid(st_geomfromgeojson(p_related_geojson),4326)::geography;
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
    -- Older clients could upload the child survey before the queued split.
    -- Recover only the same child; never overwrite a UUID collision or surveys.
    select * into related_feature from public.features
      where id=p_related_feature_id for update;
    if found then
      if related_feature.id=p_feature_id
         or related_feature.assignment_id<>current_feature.assignment_id
         or related_feature.feature_type<>current_feature.feature_type
         or not related_feature.is_new
         or related_feature.deleted_at is not null
         or related_feature.merged_into_id is not null
         or related_feature.possible_duplicate_of is not null
         or (related_feature.split_from_id is not null and related_feature.split_from_id<>p_feature_id)
         or not st_equals(related_feature.geometry::geometry,related_geometry::geometry)
         -- The existing child and remaining half must partition this parent.
         -- Permit only insignificant projection rounding (at most 1e-8 relative area).
         or st_area(st_symdifference(
              st_unaryunion(st_collect(new_geometry::geometry,related_geometry::geometry)),
              previous_geometry::geometry)) > greatest(st_area(previous_geometry::geometry)*1e-8,1e-16)
         or st_area(st_intersection(new_geometry::geometry,related_geometry::geometry))
              > greatest(st_area(previous_geometry::geometry)*1e-8,1e-16)
      then
        raise exception 'split_feature_conflict' using errcode='P0001';
      end if;
      update public.features set split_from_id=p_feature_id where id=p_related_feature_id;
    else
      insert into public.features
        (id, assignment_id, feature_type, geometry, is_new, split_from_id)
      values
        (p_related_feature_id, current_feature.assignment_id,
         current_feature.feature_type, related_geometry, true, p_feature_id);
    end if;
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


