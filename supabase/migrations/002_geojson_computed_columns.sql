-- PostgREST exposes Postgres functions whose first argument is a table
-- row as "computed columns" of that table. We add two: one for assignments,
-- one for features, both returning the geometry as GeoJSON text.
--
-- This lets the Flutter client SELECT these columns and get GeoJSON strings
-- instead of the default PostGIS EWKB hex, without changing the underlying
-- column types (we still get spatial queries, indexes, ST_DWithin, etc).

create or replace function public.boundary_polygon_geojson(public.assignments)
returns text
language sql
immutable
as $$
  select ST_AsGeoJSON($1.boundary_polygon)::text;
$$;

create or replace function public.geometry_geojson(public.features)
returns text
language sql
immutable
as $$
  select ST_AsGeoJSON($1.geometry)::text;
$$;
