-- Phase 4a fix: PostGIS-aware insert RPC for new features.
-- features.geometry is geometry(PostGIS); PostgREST can't auto-convert
-- raw GeoJSON. This RPC uses ST_GeomFromGeoJSON to parse the client's
-- geojson string and store it correctly.
create or replace function public.upload_new_feature(payload jsonb)
returns text
language plpgsql
security definer
as $$
declare
  v_id uuid := (payload->>'id')::uuid;
  v_assignment_id uuid := (payload->>'assignment_id')::uuid;
  v_feature_type text := payload->>'feature_type';
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
