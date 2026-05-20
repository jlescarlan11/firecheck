-- Flip the `photos` bucket to public so that the URLs written into the
-- exported shapefile's PHOTOS field resolve in a browser without auth.
-- QGIS users copy/paste the URL from the attribute table to view the
-- referenced photo.
--
-- RLS on the table-level (public.photos) and the storage.objects policies
-- defined in 010_storage_photos_rls.sql still control writes; flipping the
-- bucket flag only changes the public-read behavior for object retrieval
-- (i.e. `<SUPABASE_URL>/storage/v1/object/public/photos/<path>` works).

update storage.buckets
   set public = true
 where id = 'photos';
