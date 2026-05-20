-- 034_bulk_upsert_features.sql
-- Lets an enumerator publish all canonical shapefile features to the
-- server in one idempotent call right after local import, so subsequent
-- submit_attribution calls can find the parent feature row. Without this
-- the server has zero features for the assignment and every
-- submit_attribution_with_conflict_check trips its membership check
-- (the check joins via features → assignments and reports the
-- misleading "not_member" when the feature simply doesn't exist).
--
-- Feature IDs are stable across enumerators (UUID v5 of
-- assignment_id/feat_id in the client), so two enumerators importing
-- the same shapefile converge on the same rows and ON CONFLICT keeps
-- it a no-op for everyone after the first.

CREATE OR REPLACE FUNCTION public.bulk_upsert_features(
  p_assignment_id UUID,
  p_features      JSONB
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller   UUID := auth.uid();
  v_inserted INT;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.assignment_members
    WHERE assignment_id = p_assignment_id
      AND enumerator_id = v_caller
  ) THEN
    RAISE EXCEPTION 'not_member' USING ERRCODE = '42501';
  END IF;

  WITH inserted AS (
    INSERT INTO public.features
      (id, assignment_id, feature_type, geometry, is_new, created_at)
    SELECT
      (elem->>'id')::uuid,
      p_assignment_id,
      (elem->>'feature_type')::feature_type,
      ST_GeomFromGeoJSON(elem->>'geometry_geojson')::geography,
      false,
      now()
    FROM jsonb_array_elements(p_features) elem
    ON CONFLICT (id) DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO v_inserted FROM inserted;

  RETURN v_inserted;
END;
$$;

REVOKE ALL ON FUNCTION public.bulk_upsert_features(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bulk_upsert_features(UUID, JSONB) TO authenticated;
