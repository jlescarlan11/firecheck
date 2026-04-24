-- FireCheck Mobile — initial schema (Phase 0)
-- PostGIS for native geometry types
create extension if not exists postgis;

-- ============================================================
-- Enumerators (shadow of Supabase Auth users)
-- ============================================================
create table public.enumerators (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null,
  display_name text not null,
  created_at timestamptz not null default now()
);

-- ============================================================
-- Config: RA 9514 building types
-- ============================================================
create table public.ra_9514_types (
  code text primary key,
  label_en text not null,
  label_tl text not null,
  sort_order int not null default 0
);

-- ============================================================
-- Assignments
-- ============================================================
create type assignment_status as enum ('assigned', 'in_progress', 'submitted');

create table public.assignments (
  id uuid primary key,
  enumerator_id uuid not null references public.enumerators(id) on delete cascade,
  campaign_id uuid not null,
  boundary_polygon geography(Polygon, 4326) not null,
  downloaded_at timestamptz,
  submitted_at timestamptz,
  status assignment_status not null default 'assigned',
  created_at timestamptz not null default now()
);

create index on public.assignments (enumerator_id);
create index on public.assignments using gist (boundary_polygon);

-- ============================================================
-- Features (buildings + roads)
-- ============================================================
create type feature_type as enum ('building', 'road');

create table public.features (
  id uuid primary key,
  assignment_id uuid not null references public.assignments(id) on delete cascade,
  feature_type feature_type not null,
  geometry geography(Geometry, 4326) not null,
  is_new boolean not null default false,
  created_at timestamptz not null default now()
);

create index on public.features (assignment_id);
create index on public.features using gist (geometry);

-- ============================================================
-- Submissions (one feature can have multiple)
-- ============================================================
create table public.submissions (
  id uuid primary key,
  feature_id uuid not null references public.features(id) on delete cascade,
  submitted_by uuid not null references public.enumerators(id),
  does_not_exist boolean not null default false,
  remarks text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index on public.submissions (feature_id);

-- ============================================================
-- Building attributes (1:1 with submission when building)
-- ============================================================
create table public.building_attributes (
  submission_id uuid primary key references public.submissions(id) on delete cascade,
  cbms_id text,
  building_name text,
  ra_9514_type text references public.ra_9514_types(code),
  storeys int,
  material text,
  cost_is_exact boolean not null default false,
  cost_amount numeric(14,2),
  cost_estimate_range text,
  fire_fighting_facilities text[] not null default '{}',
  fire_load text[] not null default '{}'
);

-- ============================================================
-- Road attributes (1:1 with submission when road)
-- ============================================================
create table public.road_attributes (
  submission_id uuid primary key references public.submissions(id) on delete cascade,
  is_bridge boolean not null default false,
  road_name text,
  width_meters numeric(6,2),
  road_features text[] not null default '{}',
  others_description text
);

-- ============================================================
-- Household surveys (OLP) (0..1 per submission)
-- ============================================================
create type kahinaan_level as enum (
  'labis_na_mapanganib',
  'mayroong_dapat_ipangamba',
  'ligtas_ang_iyong_tahanan'
);

create table public.household_surveys (
  submission_id uuid primary key references public.submissions(id) on delete cascade,
  construction_details jsonb not null default '{}'::jsonb,
  kaayusan jsonb not null default '{}'::jsonb,
  koneksyong_elektrikal jsonb not null default '{}'::jsonb,
  kusina jsonb not null default '{}'::jsonb,
  daanan_o_labasan jsonb not null default '{}'::jsonb,
  lebel_ng_kahinaan kahinaan_level,
  safety_suggestions text
);

-- ============================================================
-- Photos
-- ============================================================
create table public.photos (
  id uuid primary key,
  submission_id uuid not null references public.submissions(id) on delete cascade,
  storage_path text not null,
  captured_at timestamptz not null,
  gps_lat numeric(10,7),
  gps_lng numeric(10,7),
  created_at timestamptz not null default now()
);

create index on public.photos (submission_id);

-- ============================================================
-- Row Level Security
-- ============================================================
alter table public.enumerators        enable row level security;
alter table public.assignments        enable row level security;
alter table public.features           enable row level security;
alter table public.submissions        enable row level security;
alter table public.building_attributes enable row level security;
alter table public.road_attributes    enable row level security;
alter table public.household_surveys  enable row level security;
alter table public.photos             enable row level security;
alter table public.ra_9514_types      enable row level security;

-- An enumerator can see and upsert their own profile
create policy enumerators_self_rw on public.enumerators
  for all using (id = auth.uid()) with check (id = auth.uid());

-- An enumerator can see and upsert their own assignments and anything under them
create policy assignments_own_rw on public.assignments
  for all using (enumerator_id = auth.uid()) with check (enumerator_id = auth.uid());

create policy features_via_assignment_rw on public.features
  for all using (
    exists (
      select 1 from public.assignments a
      where a.id = features.assignment_id and a.enumerator_id = auth.uid()
    )
  ) with check (
    exists (
      select 1 from public.assignments a
      where a.id = features.assignment_id and a.enumerator_id = auth.uid()
    )
  );

create policy submissions_via_feature_rw on public.submissions
  for all using (
    exists (
      select 1 from public.features f
      join public.assignments a on a.id = f.assignment_id
      where f.id = submissions.feature_id and a.enumerator_id = auth.uid()
    )
  ) with check (
    exists (
      select 1 from public.features f
      join public.assignments a on a.id = f.assignment_id
      where f.id = submissions.feature_id and a.enumerator_id = auth.uid()
    )
  );

create policy building_attrs_via_submission_rw on public.building_attributes
  for all using (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignments a on a.id = f.assignment_id
      where s.id = building_attributes.submission_id and a.enumerator_id = auth.uid()
    )
  ) with check (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignments a on a.id = f.assignment_id
      where s.id = building_attributes.submission_id and a.enumerator_id = auth.uid()
    )
  );

create policy road_attrs_via_submission_rw on public.road_attributes
  for all using (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignments a on a.id = f.assignment_id
      where s.id = road_attributes.submission_id and a.enumerator_id = auth.uid()
    )
  ) with check (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignments a on a.id = f.assignment_id
      where s.id = road_attributes.submission_id and a.enumerator_id = auth.uid()
    )
  );

create policy household_via_submission_rw on public.household_surveys
  for all using (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignments a on a.id = f.assignment_id
      where s.id = household_surveys.submission_id and a.enumerator_id = auth.uid()
    )
  ) with check (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignments a on a.id = f.assignment_id
      where s.id = household_surveys.submission_id and a.enumerator_id = auth.uid()
    )
  );

create policy photos_via_submission_rw on public.photos
  for all using (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignments a on a.id = f.assignment_id
      where s.id = photos.submission_id and a.enumerator_id = auth.uid()
    )
  ) with check (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignments a on a.id = f.assignment_id
      where s.id = photos.submission_id and a.enumerator_id = auth.uid()
    )
  );

-- ra_9514_types is public read-only for enumerators
create policy ra_9514_read_all on public.ra_9514_types
  for select using (auth.uid() is not null);

-- Storage bucket RLS is configured in step 3 below.
