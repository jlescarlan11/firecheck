-- Phase 4a fix (Bug 8 caught during manual happy path):
-- The photos bucket has RLS enabled but no policies granting authenticated
-- users permission to upload. SupabaseSyncApi.uploadPhotoFile fails with
-- 403 'new row violates row-level security policy'.
--
-- Grant authenticated users full read/write on objects in the photos bucket.
-- Stricter policies (e.g. only the owner can read/write their own photos)
-- can land in Phase 5 once we wire real per-user auth into submitted_by.

-- Make sure the bucket exists (idempotent — no-op if it does).
insert into storage.buckets (id, name, public)
values ('photos', 'photos', false)
on conflict (id) do nothing;

-- INSERT (upload).
drop policy if exists "Authenticated users can upload to photos" on storage.objects;
create policy "Authenticated users can upload to photos"
on storage.objects for insert
to authenticated
with check (bucket_id = 'photos');

-- UPDATE (upsert overwrites + storage_path renames).
drop policy if exists "Authenticated users can update photos" on storage.objects;
create policy "Authenticated users can update photos"
on storage.objects for update
to authenticated
using (bucket_id = 'photos')
with check (bucket_id = 'photos');

-- SELECT (signed URL generation, plus future read-back).
drop policy if exists "Authenticated users can read photos" on storage.objects;
create policy "Authenticated users can read photos"
on storage.objects for select
to authenticated
using (bucket_id = 'photos');

-- DELETE (rare; for cleanup). Not strictly needed for Phase 4a, included
-- so admins can prune.
drop policy if exists "Authenticated users can delete photos" on storage.objects;
create policy "Authenticated users can delete photos"
on storage.objects for delete
to authenticated
using (bucket_id = 'photos');
