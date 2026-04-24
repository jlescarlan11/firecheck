-- Phase 1 demo seed.
-- Inserts one campaign (optional, skipped if no campaigns table) + one
-- assignment + 10 synthetic building polygons for the existing admin@admin.com
-- user (UID 41bc0780-fa43-411c-93f4-4db926cc1ded).
-- Safe to re-run: uses ON CONFLICT DO NOTHING on every insert.

begin;

-- Assignment — rectangular boundary in Brgy. Tisa, Cebu City.
-- Center: (10.31810, 123.88270); half-size 0.0009 deg lat × 0.0007 deg lng
-- ≈ 200 m × 150 m at that latitude.
insert into public.assignments (
  id, enumerator_id, campaign_id, boundary_polygon, status, created_at
) values (
  '00000000-0000-0000-0000-000000000a01',
  '41bc0780-fa43-411c-93f4-4db926cc1ded',
  '00000000-0000-0000-0000-0000000000c1',
  ST_GeogFromText(
    'POLYGON(('
    || '123.88200 10.31720,'
    || '123.88340 10.31720,'
    || '123.88340 10.31900,'
    || '123.88200 10.31900,'
    || '123.88200 10.31720'
    || '))'
  ),
  'assigned',
  now()
)
on conflict (id) do nothing;

-- Ten synthetic buildings — 2 rows × 5 columns, each ~20 m × 15 m.
-- Positions computed from the boundary center with small offsets.
do $$
declare
  base_lat constant double precision := 10.31760;
  base_lng constant double precision := 123.88220;
  row_pitch constant double precision := 0.00035;  -- ~38 m
  col_pitch constant double precision := 0.00022;  -- ~24 m
  w constant double precision := 0.00014;          -- ~15 m
  h constant double precision := 0.00018;          -- ~20 m
  r int;
  c int;
  lat double precision;
  lng double precision;
  idx int := 0;
begin
  for r in 0..1 loop
    for c in 0..4 loop
      lat := base_lat + r * row_pitch;
      lng := base_lng + c * col_pitch;
      insert into public.features (
        id, assignment_id, feature_type, geometry, is_new, created_at
      ) values (
        ('00000000-0000-0000-0000-0000000000' || to_char(idx + 1, 'FM00'))::uuid,
        '00000000-0000-0000-0000-000000000a01',
        'building',
        ST_GeogFromText(
          'POLYGON(('
          || lng || ' ' || lat || ','
          || (lng + w) || ' ' || lat || ','
          || (lng + w) || ' ' || (lat + h) || ','
          || lng || ' ' || (lat + h) || ','
          || lng || ' ' || lat
          || '))'
        ),
        false,
        now()
      )
      on conflict (id) do nothing;
      idx := idx + 1;
    end loop;
  end loop;
end $$;

commit;
