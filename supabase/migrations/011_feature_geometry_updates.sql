-- US-9 reshape: feature_geometry_revisions table + update_feature_geometry RPC

create table public.feature_geometry_revisions (
  id              uuid primary key,
  feature_id      uuid not null references public.features(id) on delete cascade,
  edited_by       uuid references public.enumerators(id) on delete set null,
  prev_geometry   geography(Geometry, 4326) not null,
  new_geometry    geography(Geometry, 4326) not null,
  edited_at       timestamptz not null,
  override_reason text,
  created_at      timestamptz not null default now()
);

create index on public.feature_geometry_revisions (feature_id);
create index on public.feature_geometry_revisions (edited_by);

alter table public.feature_geometry_revisions enable row level security;

create policy fgr_enum_insert on public.feature_geometry_revisions
  for insert with check (
    exists (
      select 1 from public.features f
      join public.assignments a on a.id = f.assignment_id
      where f.id = feature_id and a.enumerator_id = auth.uid()
    )
  );
create policy fgr_enum_select on public.feature_geometry_revisions
  for select using (
    exists (
      select 1 from public.features f
      join public.assignments a on a.id = f.assignment_id
      where f.id = feature_id and a.enumerator_id = auth.uid()
    )
  );

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
    select 1 from public.features f
    join public.assignments a on a.id = f.assignment_id
    where f.id = p_feature_id and a.enumerator_id = auth.uid()
  ) then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  v_prev := st_geogfromgeojson(p_prev_geojson);
  v_new  := st_geogfromgeojson(p_new_geojson);

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

grant execute on function public.update_feature_geometry to authenticated;
