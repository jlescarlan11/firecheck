begin;

-- Remote assignment identity/closure is administrative authority. Mobile
-- status/progress updates are local Drift writes, not remote assignment DML.
-- Keep gateway supervisor INSERT and owner/definer maintenance controls intact.
-- TRUNCATE must also be revoked: legacy default ALL grants include it, and
-- deleting/recreating canonical rows must not reset remote closure authority.
revoke insert, update, delete, truncate on public.assignments from authenticated;

create schema firecheck_storage;
revoke all on schema firecheck_storage from public, anon, authenticated, service_role;
grant usage on schema firecheck_storage to authenticated;

-- Upload order is canonical submission -> object -> register_uploaded_photo.
-- A client-controlled owner/owner_id or path alone cannot grant write access.
-- Accepted submissions may finish evidence after remote closure (the registration
-- RPC has the same contract); deletion after closure is service cleanup only.
create function firecheck_storage.can_mutate_photo_object(object_name text, deleting boolean default false)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare v_submission_id uuid; v_photo_id uuid;
begin
  if auth.uid() is null or object_name is null or object_name !~
    '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$' then
    return false;
  end if;
  v_submission_id := split_part(object_name, '/', 1)::uuid;
  v_photo_id := split_part(split_part(object_name, '/', 2), '.', 1)::uuid;
  return exists (
    select 1 from public.submissions s
    join public.features f on f.id = s.feature_id
    join public.assignments a on a.id = f.assignment_id
    join public.assignment_members m on m.assignment_id = a.id and m.enumerator_id = auth.uid()
    where s.id = v_submission_id and s.submitted_by = auth.uid()
      and (not deleting or not a.closed_remotely)
  ) and not exists (
    select 1 from public.photos p where p.id = v_photo_id and p.submission_id <> v_submission_id
  );
end $$;
revoke all on function firecheck_storage.can_mutate_photo_object(text, boolean) from public, anon, service_role;
grant execute on function firecheck_storage.can_mutate_photo_object(text, boolean) to authenticated;

-- RLS WITH CHECK cannot compare OLD and NEW. Even if both destinations belong
-- to the actor, renaming/moving evidence invalidates its canonical reference.
-- The service can still DELETE orphaned/legacy objects. Ambiguous legacy names
-- are left in place, publicly readable, and require explicit service review.
create function firecheck_storage.keep_photo_object_identity()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (old.bucket_id = 'photos' or new.bucket_id = 'photos') and
    (old.bucket_id is distinct from new.bucket_id or old.name is distinct from new.name) then
    raise exception 'photo_object_identity_immutable' using errcode = '42501';
  end if;
  return new;
end $$;
revoke all on function firecheck_storage.keep_photo_object_identity() from public, anon, authenticated, service_role;
create trigger keep_photo_object_identity before update on storage.objects
for each row execute function firecheck_storage.keep_photo_object_identity();

drop policy "Authenticated users can upload to photos" on storage.objects;
create policy "Authenticated users can upload to photos" on storage.objects
for insert to authenticated
with check (bucket_id = 'photos' and firecheck_storage.can_mutate_photo_object(name));

drop policy "Authenticated users can update photos" on storage.objects;
create policy "Authenticated users can update photos" on storage.objects
for update to authenticated
using (bucket_id = 'photos' and firecheck_storage.can_mutate_photo_object(name))
with check (bucket_id = 'photos' and firecheck_storage.can_mutate_photo_object(name));

drop policy "Authenticated users can delete photos" on storage.objects;
create policy "Authenticated users can delete photos" on storage.objects
for delete to authenticated
using (bucket_id = 'photos' and firecheck_storage.can_mutate_photo_object(name, true));

-- Preserve 035's public GIS photo retrieval and 010's authenticated SELECT.
-- Removing membership does not revoke a known public photo URL.
commit;
