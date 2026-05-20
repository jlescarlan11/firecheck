-- 033_claim_assignment_by_name.sql
-- Auto-join: when an enumerator downloads an assignment from Drive,
-- claim membership in the same call that resolves the canonical UUID.
-- Without this, every new enumerator would need a manual INSERT into
-- assignment_members before their uploads can pass RLS — which negates
-- the value of Drive folder sharing as the access source of truth.
--
-- SECURITY DEFINER so it bypasses the membership-gated RLS on
-- public.assignments for the lookup, and so the insert into
-- assignment_members is allowed for the caller themselves.

CREATE OR REPLACE FUNCTION public.claim_assignment_by_name(p_name TEXT)
RETURNS UUID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_assignment_id UUID;
  v_caller        UUID := auth.uid();
BEGIN
  IF v_caller IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT id INTO v_assignment_id
  FROM public.assignments
  WHERE name = p_name
  LIMIT 1;

  IF v_assignment_id IS NULL THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.assignment_members (assignment_id, enumerator_id, role)
  VALUES (v_assignment_id, v_caller, 'member')
  ON CONFLICT DO NOTHING;

  RETURN v_assignment_id;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_assignment_by_name(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_assignment_by_name(TEXT) TO authenticated;
