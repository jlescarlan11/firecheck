-- supabase/migrations/019_features_proximity_trigger.sql
-- Sets features.possible_duplicate_of for newly-added user features
-- when a same-type feature already exists within the assignment's
-- dedup_proximity_meters. No-op for is_new = false (base map) rows.
--
-- IMPORTANT: BEFORE-INSERT triggers fire *before* generated columns are
-- computed, so NEW.centroid is NULL at trigger time. We re-derive the
-- centroid inline using the same expression as the stored generated
-- column on features.centroid.

create or replace function public.set_feature_possible_duplicate()
returns trigger
language plpgsql
as $$
declare
  v_threshold numeric;
begin
  if NEW.is_new is not true then
    return NEW;
  end if;

  select dedup_proximity_meters into v_threshold
  from public.assignments
  where id = NEW.assignment_id;

  if v_threshold is null then
    v_threshold := 5;
  end if;

  select id into NEW.possible_duplicate_of
  from public.features f
  where f.assignment_id = NEW.assignment_id
    and f.feature_type = NEW.feature_type
    and f.is_new = true
    and f.id <> NEW.id
    and not exists (
      -- Skip features whose latest submission is superseded with no replacement
      -- (i.e., the feature was "discarded mine" during a prior dedup resolve).
      select 1 from public.submissions s
      where s.feature_id = f.id
        and s.superseded_at is not null
        and s.superseded_by_id is null
    )
    and st_dwithin(f.centroid,
                   st_centroid(NEW.geometry::geometry)::geography,
                   v_threshold)
  order by st_distance(f.centroid,
                       st_centroid(NEW.geometry::geometry)::geography) asc
  limit 1;

  return NEW;
end;
$$;

drop trigger if exists trg_features_dedup on public.features;
create trigger trg_features_dedup
  before insert on public.features
  for each row
  execute function public.set_feature_possible_duplicate();
