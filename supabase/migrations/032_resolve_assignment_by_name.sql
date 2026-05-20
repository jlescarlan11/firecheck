-- 032_resolve_assignment_by_name.sql
-- Lets the app resolve a Drive folder name (e.g. "cebu") to the canonical
-- Supabase assignment UUID before the user has been added to
-- assignment_members. The straight SELECT on public.assignments is
-- gated by the membership RLS policy from 016, so a fresh enumerator
-- downloading an assignment for the first time would see zero rows
-- and the app would fall back to a UUID v5 derivation that doesn't
-- match what the admin created in Supabase.

CREATE OR REPLACE FUNCTION public.resolve_assignment_id_by_name(p_name TEXT)
RETURNS UUID
LANGUAGE SQL
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT id FROM public.assignments WHERE name = p_name LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.resolve_assignment_id_by_name(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_assignment_id_by_name(TEXT) TO authenticated;
