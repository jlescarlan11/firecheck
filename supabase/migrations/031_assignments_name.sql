-- 031_assignments_name.sql
-- Adds a human-readable name to assignments so the app can look up the
-- canonical Supabase UUID from the Google Drive folder name (e.g. "cebu").
-- Without this the app has to derive a UUID from the folder name, which
-- diverges from whatever UUID the admin chose when creating the assignment.

ALTER TABLE public.assignments
  ADD COLUMN IF NOT EXISTS name TEXT;

CREATE INDEX IF NOT EXISTS assignments_name_idx
  ON public.assignments (name);

-- Backfill existing assignments.
UPDATE public.assignments
  SET name = 'cebu'
  WHERE id = '00000000-0000-0000-0000-000000000a01';
