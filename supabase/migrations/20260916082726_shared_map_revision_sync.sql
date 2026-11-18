-- Durable replication. Kept off per assignment until its baseline is verified.
create schema if not exists firecheck_sync;
revoke all on schema firecheck_sync from public, anon, authenticated;

create table firecheck_sync.maps (
  assignment_id uuid primary key references public.assignments(id) on delete cascade,
  enabled boolean not null default false,
  revision bigint not null default 0,
  export_revision bigint not null default 0
);
create table firecheck_sync.bundles (
  assignment_id uuid not null references firecheck_sync.maps on delete cascade,
  revision bigint not null,
  transaction_id bigint not null,
  created_at timestamptz not null default now(),
  primary key(assignment_id, revision), unique(assignment_id, transaction_id)
);
create table firecheck_sync.changes (
  assignment_id uuid not null,
  revision bigint not null,
  feature_id uuid not null,
  payload jsonb not null,
  primary key(assignment_id, revision, feature_id),
  foreign key(assignment_id, revision) references firecheck_sync.bundles on delete cascade
);
create table firecheck_sync.current_features (
  assignment_id uuid not null references firecheck_sync.maps on delete cascade,
  feature_id uuid not null,
  revision bigint not null,
  payload jsonb not null,
  primary key(assignment_id, feature_id)
);
create table firecheck_sync.receipts (
  actor_id uuid not null,
  operation_id uuid not null,
  assignment_id uuid not null references public.assignments on delete cascade,
  payload jsonb not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  primary key(actor_id, operation_id)
);
create table firecheck_sync.export_jobs (
  assignment_id uuid primary key references firecheck_sync.maps on delete cascade,
  desired_revision bigint not null,
  lease_token uuid,
  lease_until timestamptz,
  next_attempt_at timestamptz not null default now(),
  attempts integer not null default 0,
  last_error text
);
create table firecheck_sync.exports (
  assignment_id uuid not null references firecheck_sync.maps on delete cascade,
  revision bigint not null,
  manifest jsonb not null,
  created_at timestamptz not null default now(),
  primary key(assignment_id, revision)
);
alter table firecheck_sync.maps enable row level security;
alter table firecheck_sync.bundles enable row level security;
alter table firecheck_sync.changes enable row level security;
alter table firecheck_sync.current_features enable row level security;
alter table firecheck_sync.receipts enable row level security;
alter table firecheck_sync.export_jobs enable row level security;
alter table firecheck_sync.exports enable row level security;

alter table public.submissions add column conflict_with_id uuid;
alter table public.features add column deleted_at timestamptz;
-- Existing ambiguous rows need review; never silently choose the newest upload.
with ranked as (
 select id, first_value(id) over(partition by feature_id order by created_at,id) as first_id
 from public.submissions where superseded_at is null
)
update public.submissions s set conflict_with_id=r.first_id
from ranked r where s.id=r.id and r.id<>r.first_id;

create function firecheck_sync.feature_payload(p_id uuid) returns jsonb
language sql stable security definer set search_path=public,extensions,pg_temp as $$
 select jsonb_build_object(
  'id',f.id,'assignment_id',f.assignment_id,'feature_type',f.feature_type,
  'geometry_geojson',st_asgeojson(f.geometry::geometry)::jsonb,
  'is_new',f.is_new,'created_at',f.created_at,'updated_at',f.updated_at,
  'split_from_id',f.split_from_id,'merged_into_id',f.merged_into_id,
  'deleted',f.deleted_at is not null or f.merged_into_id is not null,
  'pending_dedup',f.possible_duplicate_of is not null and f.dedup_reviewed_at is null,
  'submissions',coalesce((select jsonb_agg(jsonb_build_object(
    'id',s.id,'feature_id',s.feature_id,'feature_type',f.feature_type,
    'assignment_id',f.assignment_id,'submitted_by',s.submitted_by,
    'submitted_at',s.created_at,'updated_at',s.updated_at,'form_version',s.form_version,
    'attribute_values',jsonb_build_object('does_not_exist',s.does_not_exist,
       'remarks',s.remarks,'override_reason',s.override_reason,
       'building',to_jsonb(b)-'submission_id','road',to_jsonb(r)-'submission_id'),
    'photos',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'storage_path',p.storage_path))
      from public.photos p where p.submission_id=s.id),'[]'::jsonb)
  ) order by s.created_at,s.id)
  from public.submissions s
  left join public.building_attributes b on b.submission_id=s.id
  left join public.road_attributes r on r.submission_id=s.id
  where s.feature_id=f.id and s.superseded_at is null and s.conflict_with_id is null),'[]'::jsonb)
 ) from public.features f where f.id=p_id
$$;

-- Called by deferred triggers: child rows are complete and conflict decisions
-- have been made. One revision contains the final state of every touched feature.
create function firecheck_sync.capture(p_assignment uuid,p_feature uuid) returns void
language plpgsql security definer set search_path='' as $$
declare rev bigint; body jsonb;
begin
 insert into firecheck_sync.maps(assignment_id) values(p_assignment) on conflict do nothing;
 perform 1 from firecheck_sync.maps where assignment_id=p_assignment for update;
 select revision into rev from firecheck_sync.bundles
 where assignment_id=p_assignment and transaction_id=txid_current();
 if rev is null then
  update firecheck_sync.maps set revision=revision+1 where assignment_id=p_assignment returning revision into rev;
  insert into firecheck_sync.bundles values(p_assignment,rev,txid_current(),now());
 end if;
 body:=coalesce(firecheck_sync.feature_payload(p_feature),
   jsonb_build_object('id',p_feature,'assignment_id',p_assignment,'deleted',true));
 insert into firecheck_sync.changes values(p_assignment,rev,p_feature,body)
 on conflict(assignment_id,revision,feature_id) do update set payload=excluded.payload;
 insert into firecheck_sync.current_features values(p_assignment,p_feature,rev,body)
 on conflict(assignment_id,feature_id) do update set revision=excluded.revision,payload=excluded.payload;
 insert into firecheck_sync.export_jobs(assignment_id,desired_revision) values(p_assignment,rev)
 on conflict(assignment_id) do update set desired_revision=excluded.desired_revision;
end $$;

create function firecheck_sync.capture_trigger() returns trigger
language plpgsql security definer set search_path='' as $$
declare row_data jsonb; fid uuid; aid uuid;
begin
 row_data:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
 if tg_table_name='features' then
  fid:=(row_data->>'id')::uuid; aid:=(row_data->>'assignment_id')::uuid;
 elsif tg_table_name='submissions' then
  fid:=(row_data->>'feature_id')::uuid;
 else
  select feature_id into fid from public.submissions where id=(row_data->>'submission_id')::uuid;
 end if;
 if aid is null then select assignment_id into aid from public.features where id=fid; end if;
 -- Cascaded deletion is captured by the parent feature/submission trigger.
 if aid is not null and exists(select 1 from public.assignments where id=aid) then
  perform firecheck_sync.capture(aid,fid);
 end if;
 return null;
end $$;
do $$ declare t text; begin
 foreach t in array array['features','submissions','building_attributes','road_attributes','household_surveys','photos'] loop
  execute format('create constraint trigger shared_map_capture after insert or update or delete on public.%I deferrable initially deferred for each row execute function firecheck_sync.capture_trigger()',t);
 end loop;
end $$;

-- Membership is checked in private definer implementations; public wrappers
-- are invoker-only and expose no private tables.
create function firecheck_sync.require_member(aid uuid) returns void
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.assignment_members
  where assignment_id=aid and enumerator_id=auth.uid()) then
  raise exception 'not_member' using errcode='42501';
 end if;
end $$;
create function firecheck_sync.get_changes(aid uuid,after_rev bigint,through_rev bigint) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare hi bigint; enabled boolean; result jsonb; last_rev bigint;
begin
 perform firecheck_sync.require_member(aid);
 select m.revision,m.enabled into hi,enabled from firecheck_sync.maps m where assignment_id=aid;
 if not coalesce(enabled,false) then return jsonb_build_object('enabled',false); end if;
 if after_rev<0 or after_rev>hi or (through_rev is not null and (through_rev>hi or through_rev<after_rev)) then
  raise exception 'invalid_revision' using errcode='22023';
 end if;
 hi:=coalesce(through_rev,hi);
 select coalesce(jsonb_agg(bundle order by revision),'[]'::jsonb),coalesce(max(revision),after_rev)
 into result,last_rev from (
  select b.revision,jsonb_build_object('revision',b.revision,'features',
   coalesce((select jsonb_agg(c.payload order by c.feature_id) from firecheck_sync.changes c
    where c.assignment_id=aid and c.revision=b.revision),'[]'::jsonb)) bundle
  from firecheck_sync.bundles b where b.assignment_id=aid and b.revision>after_rev and b.revision<=hi
  order by b.revision limit 25
 ) q;
 return jsonb_build_object('enabled',true,'through_revision',hi,'next_revision',last_rev,
  'has_more',last_rev<hi,'bundles',result);
end $$;
create function public.get_shared_map_changes(p_assignment_id uuid,p_after_revision bigint default 0,p_through_revision bigint default null)
returns jsonb language sql security invoker set search_path='' as $$
 select firecheck_sync.get_changes(p_assignment_id,p_after_revision,p_through_revision)
$$;

-- Activation is an administrative operation, never granted to mobile roles.
-- The caller must first verify/import the complete source geometry.
create function firecheck_sync.activate(aid uuid) returns void
language plpgsql security definer set search_path='' as $$
declare fid uuid;
begin
 insert into firecheck_sync.maps(assignment_id) values(aid) on conflict do nothing;
 perform 1 from firecheck_sync.maps where assignment_id=aid for update;
 for fid in select id from public.features where assignment_id=aid order by id loop
  perform firecheck_sync.capture(aid,fid);
 end loop;
 update firecheck_sync.maps set enabled=true where assignment_id=aid;
end $$;

-- Replace the legacy conflict check rather than creating a bypass alongside it.
create or replace function public.submit_attribution_with_conflict_check(payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 sid uuid:=(payload#>>'{submission,id}')::uuid;
 fid uuid:=(payload#>>'{submission,feature_id}')::uuid;
 op uuid:=coalesce((payload->>'operation_id')::uuid,sid);
 base_id uuid:=nullif(payload->>'base_version_id','')::uuid;
 aid uuid; current_id uuid; result jsonb; prior firecheck_sync.receipts%rowtype;
begin
 select assignment_id into aid from public.features where id=fid;
 perform firecheck_sync.require_member(aid);
 if payload->>'feature_type' is distinct from (select feature_type::text from public.features where id=fid)
   or exists(select 1 from jsonb_each(payload) e where e.key in ('building_attributes','road_attributes','household_survey')
     and jsonb_typeof(e.value)='object' and (e.value->>'submission_id')::uuid is distinct from sid) then
  raise exception 'invalid_bundle_identity' using errcode='22023';
 end if;
 if (payload#>>'{submission,submitted_by}')::uuid is distinct from auth.uid() then
  raise exception 'invalid_author' using errcode='42501';
 end if;
 insert into firecheck_sync.maps(assignment_id) values(aid) on conflict do nothing;
 perform 1 from firecheck_sync.maps where assignment_id=aid for update;
 select * into prior from firecheck_sync.receipts where actor_id=auth.uid() and operation_id=op;
 if found then
  if prior.payload<>payload or prior.assignment_id<>aid then raise exception 'operation_payload_mismatch' using errcode='22023'; end if;
  return prior.result;
 end if;
 if exists(select 1 from public.assignments where id=aid and closed_remotely) then
  raise exception 'assignment_closed' using errcode='53300';
 end if;
 if exists(select 1 from public.submissions where id=sid) then
  -- Old clients may retry pre-migration uploads. Do not overwrite an existing UUID.
  if not exists(select 1 from public.submissions where id=sid and feature_id=fid and submitted_by=auth.uid()) then
   raise exception 'submission_id_reused' using errcode='22023';
  end if;
  select case when conflict_with_id is null then jsonb_build_object('status','committed','submission_id',sid)
   else jsonb_build_object('status','conflict','pending_id',sid,'their_submission_id',conflict_with_id) end
  into result from public.submissions where id=sid;
 else
  select id into current_id from public.submissions where feature_id=fid
   and superseded_at is null and conflict_with_id is null order by created_at desc,id limit 1;
  perform public.upload_submission_bundle(payload);
  if current_id is null or current_id=base_id then
   if current_id is not null then
    insert into public.attribution_audit_log(table_name,row_id,action,performed_by,prior_snapshot)
     select 'submissions',id,'supersede',auth.uid(),to_jsonb(s) from public.submissions s where id=current_id;
    update public.submissions set superseded_at=now(),superseded_by_id=sid where id=current_id;
   end if;
   result:=jsonb_build_object('status','committed','submission_id',sid);
  elsif coalesce((payload->>'additional_observation')::boolean,false)
    and firecheck_sync.shared_attributes_equal(current_id,sid) then
   -- Explicit additional household/observation: retain it even if answers match.
   -- It may not replace shared building/road attributes without review.
   result:=jsonb_build_object('status','committed','submission_id',sid);
  elsif public.attribution_values_equal(current_id,sid,payload->>'feature_type') then
   delete from public.submissions where id=sid;
   result:=jsonb_build_object('status','agreed_skip','submission_id',current_id);
  else
   update public.submissions set conflict_with_id=current_id where id=sid;
   result:=jsonb_build_object('status','conflict','pending_id',sid,'their_submission_id',current_id);
  end if;
 end if;
 insert into firecheck_sync.receipts(actor_id,operation_id,assignment_id,payload,result) values(auth.uid(),op,aid,payload,result);
 return result;
end $$;

-- Preserve existing authorization/audit behavior and add explicit conflict state.
alter function public.resolve_attribution(uuid,text,text) rename to resolve_attribution_legacy;
revoke all on function public.resolve_attribution_legacy(uuid,text,text) from public,anon,authenticated;
create function public.resolve_attribution(pending_id uuid,decision text,resolution_note text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare aid uuid; result jsonb; expected uuid; actual uuid;
begin
 select f.assignment_id,s.conflict_with_id into aid,expected from public.submissions s join public.features f on f.id=s.feature_id where s.id=pending_id;
 perform firecheck_sync.require_member(aid);
 perform 1 from firecheck_sync.maps where assignment_id=aid for update;
 if expected is null then raise exception 'not_pending' using errcode='22023'; end if;
 select s2.id into actual from public.submissions s join public.submissions s2 on s2.feature_id=s.feature_id
  where s.id=pending_id and s2.conflict_with_id is null and s2.superseded_at is null order by s2.created_at desc,s2.id limit 1;
 if decision='force_overwrite' and actual is distinct from expected then
  raise exception 'conflict_changed_refresh_required' using errcode='40001';
 end if;
 result:=public.resolve_attribution_legacy(pending_id,decision,resolution_note);
 if decision='force_overwrite' then update public.submissions set conflict_with_id=null where id=pending_id; end if;
 return result;
end $$;
-- Prevent direct bundle/table writes from bypassing conflict checks. Internal
-- definer RPCs retain access as owner; administrative imports are captured.
revoke execute on function public.upload_submission_bundle(jsonb) from public,anon,authenticated;
revoke insert,update,delete on public.submissions,public.building_attributes,public.road_attributes,public.household_surveys from authenticated;
revoke all on all functions in schema firecheck_sync from public,anon,authenticated;
grant usage on schema firecheck_sync to authenticated;
grant execute on function firecheck_sync.get_changes(uuid,bigint,bigint) to authenticated;
revoke all on function public.get_shared_map_changes(uuid,bigint,bigint) from public,anon;
grant execute on function public.get_shared_map_changes(uuid,bigint,bigint) to authenticated;
revoke all on function public.resolve_attribution(uuid,text,text) from public,anon;
grant execute on function public.resolve_attribution(uuid,text,text) to authenticated;

-- Repair the pre-existing geometry RPC PostGIS lookup while preserving validation.
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
set search_path = public, extensions, pg_temp
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
  -- A lost response can be retried after the feature was finalized. Match
  -- the stored operation, never accept a reused UUID with different geometry.
  if exists(select 1 from public.feature_geometry_revisions where id=p_revision_id) then
    if not exists(select 1 from public.feature_geometry_revisions r where r.id=p_revision_id
      and r.feature_id=p_feature_id and r.edited_by=auth.uid() and r.operation='reshape'
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
  previous_geometry := st_setsrid(st_geomfromgeojson(p_prev_geojson),4326)::geography;
  new_geometry := st_setsrid(st_geomfromgeojson(p_new_geojson),4326)::geography;
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


-- Mobile imports cannot resurrect stale features once the server owns a map.
alter function public.bulk_upsert_features(uuid,jsonb) rename to bulk_upsert_features_legacy;
revoke all on function public.bulk_upsert_features_legacy(uuid,jsonb) from public,anon,authenticated;
create function public.bulk_upsert_features(p_assignment_id uuid,p_features jsonb)
returns integer language plpgsql security definer set search_path='' as $$
begin
 perform firecheck_sync.require_member(p_assignment_id);
 if exists(select 1 from firecheck_sync.maps where assignment_id=p_assignment_id and enabled) then return 0; end if;
 return public.bulk_upsert_features_legacy(p_assignment_id,p_features);
end $$;
revoke all on function public.bulk_upsert_features(uuid,jsonb) from public,anon;
grant execute on function public.bulk_upsert_features(uuid,jsonb) to authenticated;

-- Automated exports have no human publisher.
alter table firecheck_gateway.versions alter column published_by drop not null;

-- Fix ambiguous form-version variable in the historical bundle wrapper.
create or replace function public.upload_submission_bundle(payload jsonb)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_form_version text := coalesce(nullif(payload->'submission'->>'form_version', ''), 'legacy-v1');
  definition jsonb;
  result text;
begin
  select fd.definition into definition
  from public.form_definitions fd where fd.version = v_form_version;
  if definition is null then
    raise exception 'unknown_form_version:%', v_form_version using errcode = '23503';
  end if;
  perform public.validate_form_constraints(payload, definition);
  result := public.upload_submission_bundle_unversioned(payload);
  update public.submissions
    set form_version = v_form_version
    where id = (payload->'submission'->>'id')::uuid;
  return result;
end
$$;
revoke all on function public.upload_submission_bundle(jsonb) from public, anon;
revoke all on function public.upload_submission_bundle(jsonb) from public, anon, authenticated;


revoke insert,update,delete on public.features from authenticated;

create table firecheck_sync.resolutions (
 actor_id uuid not null, pending_id uuid not null, kind text not null,
 assignment_id uuid not null references public.assignments on delete cascade,
 decision text not null, result jsonb not null,
 primary key(actor_id,pending_id,kind)
);
alter table firecheck_sync.resolutions enable row level security;
create or replace function public.resolve_attribution(pending_id uuid,decision text,resolution_note text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare aid uuid; fid uuid; expected uuid; actual uuid; result jsonb; saved firecheck_sync.resolutions%rowtype;
begin
 select * into saved from firecheck_sync.resolutions r where r.actor_id=auth.uid() and r.pending_id=resolve_attribution.pending_id and r.kind='attribution';
 if found then
  perform firecheck_sync.require_member(saved.assignment_id);
  if saved.decision<>decision then raise exception 'resolution_already_applied' using errcode='22023'; end if;
  return saved.result;
 end if;
 select f.assignment_id,s.feature_id,s.conflict_with_id into aid,fid,expected
 from public.submissions s join public.features f on f.id=s.feature_id where s.id=pending_id;
 perform firecheck_sync.require_member(aid);
 perform 1 from firecheck_sync.maps where assignment_id=aid for update;
 if exists(select 1 from public.assignments where id=aid and closed_remotely) then raise exception 'assignment_closed' using errcode='53300'; end if;
 if expected is null or decision not in ('keep_theirs','force_overwrite') then raise exception 'not_pending_or_invalid_decision' using errcode='22023'; end if;
 select s.id into actual from public.submissions s where s.feature_id=fid
  and s.conflict_with_id is null and s.superseded_at is null order by s.created_at desc,s.id limit 1;
 if decision='force_overwrite' then
  if actual is distinct from expected then raise exception 'conflict_changed_refresh_required' using errcode='40001'; end if;
  insert into public.attribution_audit_log(table_name,row_id,action,performed_by,prior_snapshot,resolution_note)
    select 'submissions',s.id,'force_overwrite',auth.uid(),to_jsonb(s),resolve_attribution.resolution_note
    from public.submissions s where s.id=actual;
  update public.submissions set superseded_at=now(),superseded_by_id=pending_id where id=actual;
  update public.submissions set conflict_with_id=null where id=pending_id;
  actual:=pending_id;
 else
  delete from public.submissions where id=pending_id;
 end if;
 result:=jsonb_build_object('resolved',decision,'canonical_submission_id',actual);
 insert into firecheck_sync.resolutions values(auth.uid(),pending_id,'attribution',aid,decision,result);
 return result;
end $$;

alter function public.resolve_new_feature(uuid,text,text) rename to resolve_new_feature_legacy;
revoke all on function public.resolve_new_feature_legacy(uuid,text,text) from public,anon,authenticated;
create function public.resolve_new_feature(pending_id uuid,decision text,resolution_note text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare aid uuid; other uuid; result jsonb; saved firecheck_sync.resolutions%rowtype;
begin
 select * into saved from firecheck_sync.resolutions r where r.actor_id=auth.uid() and r.pending_id=resolve_new_feature.pending_id and r.kind='feature';
 if found then
  perform firecheck_sync.require_member(saved.assignment_id);
  if saved.decision<>decision then raise exception 'resolution_already_applied' using errcode='22023'; end if;
  return saved.result;
 end if;
 select assignment_id,possible_duplicate_of into aid,other from public.features where id=pending_id;
 perform firecheck_sync.require_member(aid);
 perform 1 from firecheck_sync.maps where assignment_id=aid for update;
 if exists(select 1 from public.assignments where id=aid and closed_remotely) then raise exception 'assignment_closed' using errcode='53300'; end if;
 result:=public.resolve_new_feature_legacy(pending_id,decision,resolution_note);
 if decision='discard_mine' then update public.features set deleted_at=now() where id=pending_id;
 elsif decision='replace_theirs' then update public.features set deleted_at=now() where id=other;
 end if;
 insert into firecheck_sync.resolutions values(auth.uid(),pending_id,'feature',aid,decision,result);
 return result;
end $$;
revoke all on function public.resolve_new_feature(uuid,text,text) from public,anon;
grant execute on function public.resolve_new_feature(uuid,text,text) to authenticated;

-- Agreement must include all submitted answers, not just typed GIS attributes.
create or replace function public.attribution_values_equal(a_submission_id uuid,b_submission_id uuid,v_feature_type text)
returns boolean language sql stable security invoker set search_path='' as $$
 select (
  select jsonb_build_object('does_not_exist',s.does_not_exist,'remarks',s.remarks,
   'override_reason',s.override_reason,'form_version',s.form_version,
   'building',to_jsonb(b)-'submission_id','road',to_jsonb(r)-'submission_id',
   'household',to_jsonb(h)-'submission_id')
  from public.submissions s
  left join public.building_attributes b on b.submission_id=s.id
  left join public.road_attributes r on r.submission_id=s.id
  left join public.household_surveys h on h.submission_id=s.id where s.id=a_submission_id
 ) is not distinct from (
  select jsonb_build_object('does_not_exist',s.does_not_exist,'remarks',s.remarks,
   'override_reason',s.override_reason,'form_version',s.form_version,
   'building',to_jsonb(b)-'submission_id','road',to_jsonb(r)-'submission_id',
   'household',to_jsonb(h)-'submission_id')
  from public.submissions s
  left join public.building_attributes b on b.submission_id=s.id
  left join public.road_attributes r on r.submission_id=s.id
  left join public.household_surveys h on h.submission_id=s.id where s.id=b_submission_id
 )
$$;

create function public.register_uploaded_photo(p_photo_id uuid,p_submission_id uuid,p_storage_path text,p_captured_at timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare aid uuid;
begin
 select f.assignment_id into aid from public.submissions s join public.features f on f.id=s.feature_id
 where s.id=p_submission_id and s.submitted_by=auth.uid();
 perform firecheck_sync.require_member(aid);
 if p_storage_path<>p_submission_id::text || '/' || p_photo_id::text || '.jpg' or p_captured_at is null then
  raise exception 'invalid_photo_metadata' using errcode='22023';
 end if;
 if exists(select 1 from public.photos where id=p_photo_id and submission_id<>p_submission_id) then
  raise exception 'photo_id_reused' using errcode='22023';
 end if;
 insert into public.photos(id,submission_id,storage_path,captured_at) values(p_photo_id,p_submission_id,p_storage_path,p_captured_at)
 on conflict(id) do update set storage_path=excluded.storage_path
 where photos.storage_path is distinct from excluded.storage_path;
end $$;
revoke all on function public.register_uploaded_photo(uuid,uuid,text,timestamptz) from public,anon;
grant execute on function public.register_uploaded_photo(uuid,uuid,text,timestamptz) to authenticated;

create function firecheck_sync.shared_attributes_equal(a uuid,b uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select (select jsonb_build_object('does_not_exist',s.does_not_exist,
   'building',to_jsonb(ba)-'submission_id','road',to_jsonb(ra)-'submission_id')
   from public.submissions s left join public.building_attributes ba on ba.submission_id=s.id
   left join public.road_attributes ra on ra.submission_id=s.id where s.id=a)
 is not distinct from
 (select jsonb_build_object('does_not_exist',s.does_not_exist,
   'building',to_jsonb(ba)-'submission_id','road',to_jsonb(ra)-'submission_id')
   from public.submissions s left join public.building_attributes ba on ba.submission_id=s.id
   left join public.road_attributes ra on ra.submission_id=s.id where s.id=b)
$$;
revoke all on function firecheck_sync.shared_attributes_equal(uuid,uuid) from public,anon,authenticated;

-- Dedicated gateway login permissions; mobile JWT roles cannot assume this role.
grant usage on schema firecheck_sync to firecheck_gateway_server;
grant select,insert,update on firecheck_sync.maps to firecheck_gateway_server;
grant select,update on firecheck_sync.export_jobs to firecheck_gateway_server;
grant select,insert,update on firecheck_sync.exports to firecheck_gateway_server;
grant select on firecheck_sync.current_features to firecheck_gateway_server;
grant execute on function firecheck_sync.activate(uuid) to firecheck_gateway_server;
create policy gateway_maps on firecheck_sync.maps for all to firecheck_gateway_server using(true) with check(true);
create policy gateway_export_jobs on firecheck_sync.export_jobs for all to firecheck_gateway_server using(true) with check(true);
create policy gateway_exports on firecheck_sync.exports for all to firecheck_gateway_server using(true) with check(true);
create policy gateway_current_features on firecheck_sync.current_features for select to firecheck_gateway_server using(true);
grant select,insert on public.features to firecheck_gateway_server;
create policy gateway_baseline_read on public.features for select to firecheck_gateway_server using(true);
create policy gateway_baseline_insert on public.features for insert to firecheck_gateway_server with check(true);

-- New features share the same closed-map and geometry validation boundary.
alter function public.submit_new_feature_with_dedup_check(jsonb) rename to submit_new_feature_with_dedup_check_legacy;
revoke all on function public.submit_new_feature_with_dedup_check_legacy(jsonb) from public,anon,authenticated;
alter function public.submit_new_feature_with_dedup_check_legacy(jsonb) set search_path=public,extensions,pg_temp;
alter function public.upload_new_feature(jsonb) set search_path=public,extensions,pg_temp;
alter function public.upload_submission_bundle_unversioned(jsonb) set search_path=public,extensions,pg_temp;
alter function public.resolve_attribution_legacy(uuid,text,text) set search_path=public,extensions,pg_temp;
alter function public.resolve_new_feature_legacy(uuid,text,text) set search_path=public,extensions,pg_temp;
create function public.submit_new_feature_with_dedup_check(payload jsonb) returns jsonb
language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare aid uuid:=(payload->>'assignment_id')::uuid; fid uuid:=(payload->>'id')::uuid; shape geometry;
begin
 perform firecheck_sync.require_member(aid);
 insert into firecheck_sync.maps(assignment_id) values(aid) on conflict do nothing;
 perform 1 from firecheck_sync.maps where assignment_id=aid for update;
 if exists(select 1 from public.assignments where id=aid and closed_remotely) then
  raise exception 'assignment_closed' using errcode='53300';
 end if;
 if exists(select 1 from public.features where id=fid and assignment_id<>aid) then
  raise exception 'feature_id_reused' using errcode='22023';
 end if;
 if nullif(payload->>'submitted_by','') is not null and (payload->>'submitted_by')::uuid is distinct from auth.uid() then
  raise exception 'invalid_author' using errcode='42501';
 end if;
 shape:=st_setsrid(st_geomfromgeojson(payload->>'geometry_geojson'),4326);
 if not st_isvalid(shape) or not exists(select 1 from public.assignments
    where id=aid and st_coveredby(shape,boundary_polygon::geometry))
    or (payload->>'feature_type'='building' and geometrytype(shape) not in ('POLYGON','MULTIPOLYGON'))
    or (payload->>'feature_type'='road' and geometrytype(shape) not in ('LINESTRING','MULTILINESTRING')) then
  raise exception 'invalid_or_outside_boundary' using errcode='22023';
 end if;
 return public.submit_new_feature_with_dedup_check_legacy(payload);
end $$;
revoke all on function public.submit_new_feature_with_dedup_check(jsonb) from public,anon;
grant execute on function public.submit_new_feature_with_dedup_check(jsonb) to authenticated;

-- Snapshot metadata participates in the revision too. Otherwise a rename or
-- boundary edit could change the bytes of an already published version.
create function firecheck_sync.capture_assignment_metadata() returns trigger
language plpgsql security definer set search_path='' as $$
declare rev bigint;
begin
 if (to_jsonb(old)-'downloaded_at'-'submitted_at') = (to_jsonb(new)-'downloaded_at'-'submitted_at') then return null; end if;
 insert into firecheck_sync.maps(assignment_id) values(new.id) on conflict do nothing;
 perform 1 from firecheck_sync.maps where assignment_id=new.id for update;
 select revision into rev from firecheck_sync.bundles where assignment_id=new.id and transaction_id=txid_current();
 if rev is null then
  update firecheck_sync.maps set revision=revision+1 where assignment_id=new.id returning revision into rev;
  insert into firecheck_sync.bundles values(new.id,rev,txid_current(),now());
 end if;
 insert into firecheck_sync.export_jobs(assignment_id,desired_revision) values(new.id,rev)
 on conflict(assignment_id) do update set desired_revision=excluded.desired_revision;
 return null;
end $$;
revoke all on function firecheck_sync.capture_assignment_metadata() from public,anon,authenticated;
create constraint trigger shared_map_metadata_capture after update on public.assignments
 deferrable initially deferred for each row execute function firecheck_sync.capture_assignment_metadata();
