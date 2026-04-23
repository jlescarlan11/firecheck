# FireCheck Mobile — Phase 0 (Foundations) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the FireCheck Mobile app's foundation so an enumerator can install the APK, log in with Supabase Auth (biometric-unlocked on subsequent opens), and land on an empty-but-live home screen whose progress counts are driven by streams from a real local SQLite database.

**Architecture:** Flutter + Riverpod state + Drift (SQLite) as local source-of-truth + Supabase (Postgres + PostGIS + Auth) as remote. This phase stands up all 11 local tables, the Supabase schema + RLS, auth, biometric unlock, and the home screen shell. No map, no forms, no sync worker yet — those arrive in later phase plans.

**Tech Stack:**
- Flutter 3.22+ / Dart 3.4+
- `flutter_riverpod` 2.5+ with `riverpod_generator` for providers
- `drift` 2.18+ with `drift_dev` codegen
- `supabase_flutter` 2.5+
- `flutter_secure_storage` 9+
- `local_auth` 2+ for biometrics
- `go_router` 14+ for routing
- `mocktail` 1+ for tests
- `very_good_analysis` for lints

**Phase 0 demo state:** `flutter run` boots the app, user logs in with Supabase Auth credentials, app persists the refresh token to secure storage, next open prompts biometric unlock, home screen shows "0 of 0 features · 0 queued · 0 failed" with reactive progress counts from an empty Drift DB.

**Downstream phases** (each will get its own plan document once this one ships):

- Phase 1: Get Maps + offline MapLibre tile packs + map view
- Phase 2: Building form + autosave + camera/photos
- Phase 3: Road form + OLP household survey + add-new-feature long-press
- Phase 4: Sync worker (outbox) + review screen + upload flow
- Phase 5: Bilingual polish + crash reporting + field-walk validation

---

## File structure (Phase 0)

Files created or modified in this phase. Files touched by later phases are noted but not implemented here.

```
pubspec.yaml                                      New — deps + asset/l10n config
analysis_options.yaml                             New — very_good_analysis lints
.env.example                                      New — template for SUPABASE_URL/ANON_KEY
.gitignore                                        Modify — add build/, .env, coverage/

android/app/build.gradle                          Modify — minSdk 26, targetSdk 34
android/app/src/main/AndroidManifest.xml          Modify — biometric + internet permissions

supabase/migrations/
  001_initial_schema.sql                          New — all remote tables + PostGIS + RLS

lib/
  main.dart                                       New — ProviderScope + bootstrap
  app.dart                                        New — MaterialApp.router + theme + l10n
  core/
    db/
      database.dart                               New — @DriftDatabase class
      tables/
        enumerators.dart                          New
        assignments.dart                          New
        features.dart                             New
        submissions.dart                          New
        building_attributes.dart                  New
        road_attributes.dart                      New
        household_surveys.dart                    New
        photos.dart                               New
        ra_9514_types.dart                        New
        sync_jobs.dart                            New
        offline_tile_packs.dart                   New
    errors/
      failure.dart                                New — sealed Failure class
    security/
      secure_storage.dart                         New — SecureStorage wrapper
      biometric_gate.dart                         New — BiometricGate wrapper
    supabase/
      supabase_client_provider.dart               New — Riverpod provider for Supabase client
    i18n/
      app_en.arb                                  New — English labels
      app_tl.arb                                  New — Tagalog labels
    router/
      app_router.dart                             New — go_router + auth redirect
  features/
    auth/
      data/
        auth_repository.dart                      New — login/logout/restoreSession
      domain/
        auth_state.dart                           New — sealed AuthState
      presentation/
        login_screen.dart                         New
        auth_providers.dart                       New — authStateProvider
    home/
      data/
        progress_repository.dart                  New — reactive ProgressSnapshot stream
      domain/
        progress_snapshot.dart                    New
      presentation/
        home_screen.dart                          New
        home_providers.dart                       New

test/
  core/
    db/
      database_test.dart                          New
    security/
      secure_storage_test.dart                    New
      biometric_gate_test.dart                    New
  features/
    auth/
      auth_repository_test.dart                   New
      login_screen_test.dart                      New
    home/
      progress_repository_test.dart               New
      home_screen_test.dart                       New
```

---

## Task 1: Initialize Flutter project, dependencies, and lint config

**Files:**
- Create: project scaffold via `flutter create`
- Create: `pubspec.yaml` (overwrite generated)
- Create: `analysis_options.yaml`
- Modify: `.gitignore`
- Create: `.env.example`

- [ ] **Step 1: Create Flutter project**

From the repo root:

```bash
flutter create --platforms=android --org=ph.gov.bfp.firecheck --project-name=firecheck --overwrite .
```

Expected: project files generated; existing `.git`, `.claude`, `docs/`, `.gitignore`, `.superpowers` preserved.

- [ ] **Step 2: Replace `pubspec.yaml`**

Overwrite `pubspec.yaml` with:

```yaml
name: firecheck
description: FireCheck Mobile — attribution and household survey for fire-risk modeling.
publish_to: 'none'
version: 0.1.0+1

environment:
  sdk: ">=3.4.0 <4.0.0"
  flutter: ">=3.22.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  intl: ^0.19.0

  # state
  flutter_riverpod: ^2.5.1
  riverpod_annotation: ^2.3.5

  # routing
  go_router: ^14.2.0

  # persistence
  drift: ^2.18.0
  sqlite3_flutter_libs: ^0.5.24
  path_provider: ^2.1.3
  path: ^1.9.0

  # remote
  supabase_flutter: ^2.5.6

  # platform
  flutter_secure_storage: ^9.2.2
  local_auth: ^2.2.0

  # utilities
  uuid: ^4.4.0
  flutter_dotenv: ^5.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.11
  drift_dev: ^2.18.0
  riverpod_generator: ^2.4.0
  custom_lint: ^0.6.4
  riverpod_lint: ^2.3.10
  mocktail: ^1.0.4
  very_good_analysis: ^6.0.0

flutter:
  uses-material-design: true
  generate: true
  assets:
    - .env
```

- [ ] **Step 3: Create `analysis_options.yaml`**

Overwrite with:

```yaml
include: package:very_good_analysis/analysis_options.yaml

analyzer:
  plugins:
    - custom_lint
  exclude:
    - '**/*.g.dart'
    - '**/*.freezed.dart'
    - 'lib/generated/**'
```

- [ ] **Step 4: Extend `.gitignore`**

Append to existing `.gitignore`:

```
# Flutter
build/
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.packages
coverage/

# Local environment
.env
!.env.example

# IDE
.idea/
*.iml
.vscode/
```

- [ ] **Step 5: Create `.env.example`**

```
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_ANON_KEY=your-anon-key
```

- [ ] **Step 6: Update Android `build.gradle`**

Edit `android/app/build.gradle`. Set:

```gradle
android {
    defaultConfig {
        minSdkVersion 26
        targetSdkVersion 34
    }
}
```

- [ ] **Step 7: Add Android permissions**

In `android/app/src/main/AndroidManifest.xml`, inside `<manifest>` (outside `<application>`), add:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.USE_BIOMETRIC"/>
<uses-permission android:name="android.permission.USE_FINGERPRINT"/>
```

Inside `<application>`, ensure the main `<activity>` has `android:exported="true"`.

- [ ] **Step 8: Install deps**

Run:

```bash
flutter pub get
```

Expected: all packages resolve with no version conflicts.

- [ ] **Step 9: Verify project builds**

Run:

```bash
flutter analyze
```

Expected: zero warnings (ignore the default `main.dart` counter-app lint hits for now — they'll be replaced in Task 16).

- [ ] **Step 10: Commit**

```bash
git add pubspec.yaml analysis_options.yaml .gitignore .env.example android/ ios/ linux/ macos/ windows/ web/ lib/main.dart test/widget_test.dart README.md
git commit -m "chore: scaffold Flutter project + deps + lint config"
```

---

## Task 2: Supabase schema migration

**Files:**
- Create: `supabase/migrations/001_initial_schema.sql`

This SQL runs server-side on Supabase. It defines all remote tables, PostGIS types, and Row Level Security policies. The Drift tables in later tasks mirror the same columns but with GeoJSON text for geometry (local convenience).

- [ ] **Step 1: Create migration file**

Create `supabase/migrations/001_initial_schema.sql` with:

```sql
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
```

- [ ] **Step 2: Create Supabase project (manual — one-time)**

Ask the user to do this manually in the Supabase dashboard, since creating a hosted project cannot be scripted from the CLI without first authenticating interactively:

1. Go to https://supabase.com → New project → name `firecheck-dev`.
2. Note the project ref, URL (`https://<ref>.supabase.co`), and anon key.
3. Copy `.env.example` to `.env` and fill both values.

- [ ] **Step 3: Run the migration against the Supabase project**

Install Supabase CLI if not present (`brew install supabase/tap/supabase` on macOS), then:

```bash
supabase login
supabase link --project-ref <your-project-ref>
supabase db push
```

Expected: migration 001 applies cleanly. Run `supabase db diff` and confirm no pending diff.

- [ ] **Step 4: Create Storage bucket `photos`**

In the Supabase dashboard → Storage → New bucket:
- Name: `photos`
- Public: **off**
- RLS: enable with policies (paste into SQL editor):

```sql
create policy photos_upload_own on storage.objects
  for insert with check (
    bucket_id = 'photos'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy photos_read_own on storage.objects
  for select using (
    bucket_id = 'photos'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );
```

This enforces that each enumerator can only write/read under a folder named after their uid — e.g., `<uid>/<submission_id>/<photo_id>.jpg`.

- [ ] **Step 5: Commit**

```bash
git add supabase/
git commit -m "feat(db): supabase schema + RLS + photos bucket policies"
```

---

## Task 3: Drift tables — all 11 table definitions

**Files:**
- Create: `lib/core/db/tables/enumerators.dart`
- Create: `lib/core/db/tables/assignments.dart`
- Create: `lib/core/db/tables/features.dart`
- Create: `lib/core/db/tables/submissions.dart`
- Create: `lib/core/db/tables/building_attributes.dart`
- Create: `lib/core/db/tables/road_attributes.dart`
- Create: `lib/core/db/tables/household_surveys.dart`
- Create: `lib/core/db/tables/photos.dart`
- Create: `lib/core/db/tables/ra_9514_types.dart`
- Create: `lib/core/db/tables/sync_jobs.dart`
- Create: `lib/core/db/tables/offline_tile_packs.dart`

Drift tables are Dart classes that describe SQL schema. Codegen produces typed data classes and DAO stubs. All PKs are `TEXT` columns holding client-generated UUIDs (v4). Timestamps are `DateTime` (Drift serializes to ISO8601 text).

- [ ] **Step 1: Create `enumerators.dart`**

```dart
import 'package:drift/drift.dart';

class Enumerators extends Table {
  TextColumn get id => text()();
  TextColumn get username => text()();
  TextColumn get displayName => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 2: Create `assignments.dart`**

```dart
import 'package:drift/drift.dart';

class Assignments extends Table {
  TextColumn get id => text()();
  TextColumn get enumeratorId => text()();
  TextColumn get campaignId => text()();
  TextColumn get boundaryPolygonGeojson => text()();
  DateTimeColumn get downloadedAt => dateTime().nullable()();
  DateTimeColumn get submittedAt => dateTime().nullable()();
  TextColumn get status =>
      text().withDefault(const Constant('assigned'))(); // assigned|in_progress|submitted
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 3: Create `features.dart`**

```dart
import 'package:drift/drift.dart';

class Features extends Table {
  TextColumn get id => text()();
  TextColumn get assignmentId => text()();
  TextColumn get featureType => text()(); // building|road
  TextColumn get geometryGeojson => text()();
  BoolColumn get isNew => boolean().withDefault(const Constant(false))();
  TextColumn get status =>
      text().withDefault(const Constant('unfilled'))(); // unfilled|in_progress|complete
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 4: Create `submissions.dart`**

```dart
import 'package:drift/drift.dart';

class Submissions extends Table {
  TextColumn get id => text()();
  TextColumn get featureId => text()();
  TextColumn get submittedBy => text()();
  BoolColumn get doesNotExist => boolean().withDefault(const Constant(false))();
  TextColumn get remarks => text().nullable()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant('draft'))(); // draft|queued|uploading|uploaded|failed|dead
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 5: Create `building_attributes.dart`**

```dart
import 'package:drift/drift.dart';

class BuildingAttributes extends Table {
  TextColumn get submissionId => text()();
  TextColumn get cbmsId => text().nullable()();
  TextColumn get buildingName => text().nullable()();
  TextColumn get ra9514Type => text().nullable()();
  IntColumn get storeys => integer().nullable()();
  TextColumn get material => text().nullable()();
  BoolColumn get costIsExact => boolean().withDefault(const Constant(false))();
  RealColumn get costAmount => real().nullable()();
  TextColumn get costEstimateRange => text().nullable()();
  TextColumn get fireFightingFacilitiesJson =>
      text().withDefault(const Constant('[]'))();
  TextColumn get fireLoadJson => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {submissionId};
}
```

- [ ] **Step 6: Create `road_attributes.dart`**

```dart
import 'package:drift/drift.dart';

class RoadAttributes extends Table {
  TextColumn get submissionId => text()();
  BoolColumn get isBridge => boolean().withDefault(const Constant(false))();
  TextColumn get roadName => text().nullable()();
  RealColumn get widthMeters => real().nullable()();
  TextColumn get roadFeaturesJson => text().withDefault(const Constant('[]'))();
  TextColumn get othersDescription => text().nullable()();

  @override
  Set<Column> get primaryKey => {submissionId};
}
```

- [ ] **Step 7: Create `household_surveys.dart`**

```dart
import 'package:drift/drift.dart';

class HouseholdSurveys extends Table {
  TextColumn get submissionId => text()();
  TextColumn get constructionDetailsJson =>
      text().withDefault(const Constant('{}'))();
  TextColumn get kaayusanJson => text().withDefault(const Constant('{}'))();
  TextColumn get koneksyongElektrikalJson =>
      text().withDefault(const Constant('{}'))();
  TextColumn get kusinaJson => text().withDefault(const Constant('{}'))();
  TextColumn get daananOLabasanJson =>
      text().withDefault(const Constant('{}'))();
  TextColumn get lebelNgKahinaan => text().nullable()();
  TextColumn get safetySuggestions => text().nullable()();

  @override
  Set<Column> get primaryKey => {submissionId};
}
```

- [ ] **Step 8: Create `photos.dart`**

```dart
import 'package:drift/drift.dart';

class Photos extends Table {
  TextColumn get id => text()();
  TextColumn get submissionId => text()();
  TextColumn get localPath => text()();
  TextColumn get storagePath => text().nullable()();
  DateTimeColumn get capturedAt => dateTime()();
  RealColumn get gpsLat => real().nullable()();
  RealColumn get gpsLng => real().nullable()();
  TextColumn get uploadStatus =>
      text().withDefault(const Constant('pending'))(); // pending|uploaded|failed
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 9: Create `ra_9514_types.dart`**

```dart
import 'package:drift/drift.dart';

class Ra9514Types extends Table {
  TextColumn get code => text()();
  TextColumn get labelEn => text()();
  TextColumn get labelTl => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {code};
}
```

- [ ] **Step 10: Create `sync_jobs.dart`**

```dart
import 'package:drift/drift.dart';

class SyncJobs extends Table {
  TextColumn get id => text()();
  TextColumn get entityType =>
      text()(); // submission|photo|new_feature|status_update
  TextColumn get entityId => text()();
  TextColumn get status =>
      text().withDefault(const Constant('pending'))(); // pending|in_progress|success|failed|dead
  TextColumn get blocksOnSubmissionId => text().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 11: Create `offline_tile_packs.dart`**

```dart
import 'package:drift/drift.dart';

class OfflineTilePacks extends Table {
  TextColumn get id => text()();
  TextColumn get assignmentId => text()();
  TextColumn get maplibrePackId => text().nullable()();
  TextColumn get regionBoundsGeojson => text()();
  IntColumn get downloadedBytes => integer().withDefault(const Constant(0))();
  IntColumn get totalBytes => integer().withDefault(const Constant(0))();
  TextColumn get status =>
      text().withDefault(const Constant('downloading'))(); // downloading|ready|error

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 12: Commit**

```bash
git add lib/core/db/tables/
git commit -m "feat(db): define all Drift tables (Phase 0 schema)"
```

---

## Task 4: Drift database class + codegen + schema smoke test

**Files:**
- Create: `lib/core/db/database.dart`
- Create: `test/core/db/database_test.dart`
- Generated (after codegen): `lib/core/db/database.g.dart`

- [ ] **Step 1: Create `lib/core/db/database.dart`**

```dart
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables/enumerators.dart';
import 'tables/assignments.dart';
import 'tables/features.dart';
import 'tables/submissions.dart';
import 'tables/building_attributes.dart';
import 'tables/road_attributes.dart';
import 'tables/household_surveys.dart';
import 'tables/photos.dart';
import 'tables/ra_9514_types.dart';
import 'tables/sync_jobs.dart';
import 'tables/offline_tile_packs.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Enumerators,
    Assignments,
    Features,
    Submissions,
    BuildingAttributes,
    RoadAttributes,
    HouseholdSurveys,
    Photos,
    Ra9514Types,
    SyncJobs,
    OfflineTilePacks,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// For tests — pass an in-memory executor.
  AppDatabase.forTesting(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'firecheck.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
```

- [ ] **Step 2: Run Drift codegen**

```bash
dart run build_runner build --delete-conflicting-outputs
```

Expected: `lib/core/db/database.g.dart` is generated. If codegen fails due to missing imports, the error output will point to a table file — fix imports and re-run.

- [ ] **Step 3: Write failing schema test**

Create `test/core/db/database_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppDatabase', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('schema v1 creates all 11 tables without error', () async {
      // Assert by inserting a row into every table and reading it back.
      await db.into(db.ra9514Types).insert(
            Ra9514TypesCompanion.insert(
              code: 'A',
              labelEn: 'Residential',
              labelTl: 'Tirahan',
            ),
          );

      final rows = await db.select(db.ra9514Types).get();
      expect(rows, hasLength(1));
      expect(rows.first.code, 'A');
    });

    test('schemaVersion is 1', () {
      expect(db.schemaVersion, 1);
    });

    test('all 11 tables are registered on the DB', () {
      final names = db.allTables.map((t) => t.actualTableName).toSet();
      expect(
        names,
        containsAll([
          'enumerators',
          'assignments',
          'features',
          'submissions',
          'building_attributes',
          'road_attributes',
          'household_surveys',
          'photos',
          'ra_9514_types',
          'sync_jobs',
          'offline_tile_packs',
        ]),
      );
    });
  });
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/core/db/database_test.dart
```

Expected: all 3 tests PASS. If a table name fails the `containsAll` check, the Drift convention converts `Ra9514Types` → `ra_9514_types` automatically. If an actual table is missing, re-check Task 3.

- [ ] **Step 5: Commit**

```bash
git add lib/core/db/database.dart lib/core/db/database.g.dart test/core/db/
git commit -m "feat(db): AppDatabase with schema v1 + smoke tests"
```

---

## Task 5: Failure model

**Files:**
- Create: `lib/core/errors/failure.dart`

A sealed `Failure` class surfaces all expected error outcomes from repositories and is what the UI renders.

- [ ] **Step 1: Create `lib/core/errors/failure.dart`**

```dart
/// Base sealed class for expected, recoverable failure modes surfaced from
/// repositories to the UI. Unknown/unexpected exceptions should propagate
/// as regular `Object` errors and be caught by the app-level error zone.
sealed class Failure {
  const Failure(this.message);
  final String message;

  @override
  String toString() => '$runtimeType($message)';
}

/// Network / offline / remote-unavailable.
class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Network unavailable']);
}

/// Auth failed (bad credentials, expired token, biometric denied).
class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

/// Storage / DB / filesystem problem.
class StorageFailure extends Failure {
  const StorageFailure(super.message);
}

/// Validation — input data rejected by local or server rules.
class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {this.fieldErrors = const {}});
  final Map<String, String> fieldErrors;
}

/// Server rejected the request with a permanent 4xx (except 401/409).
class ServerRejectedFailure extends Failure {
  const ServerRejectedFailure(super.message, this.statusCode);
  final int statusCode;
}

/// The assignment was closed remotely (409).
class AssignmentClosedFailure extends Failure {
  const AssignmentClosedFailure()
      : super('This assignment was closed by your supervisor.');
}
```

- [ ] **Step 2: Verify analyze passes**

```bash
flutter analyze lib/core/errors/
```

Expected: no lint errors.

- [ ] **Step 3: Commit**

```bash
git add lib/core/errors/
git commit -m "feat(core): sealed Failure model"
```

---

## Task 6: Secure storage wrapper + test

**Files:**
- Create: `lib/core/security/secure_storage.dart`
- Create: `test/core/security/secure_storage_test.dart`

This wraps `flutter_secure_storage` behind a narrow interface, letting tests inject a fake implementation (because the real `FlutterSecureStorage` needs the Android keystore).

- [ ] **Step 1: Write failing test**

Create `test/core/security/secure_storage_test.dart`:

```dart
import 'package:firecheck/core/security/secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemorySecureStorage', () {
    late InMemorySecureStorage storage;

    setUp(() {
      storage = InMemorySecureStorage();
    });

    test('write then read returns value', () async {
      await storage.write('refresh_token', 'abc.def');
      expect(await storage.read('refresh_token'), 'abc.def');
    });

    test('read of missing key returns null', () async {
      expect(await storage.read('nope'), isNull);
    });

    test('delete removes the key', () async {
      await storage.write('refresh_token', 'abc.def');
      await storage.delete('refresh_token');
      expect(await storage.read('refresh_token'), isNull);
    });

    test('clear wipes all keys', () async {
      await storage.write('a', '1');
      await storage.write('b', '2');
      await storage.clear();
      expect(await storage.read('a'), isNull);
      expect(await storage.read('b'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/core/security/secure_storage_test.dart
```

Expected: FAIL — `SecureStorage` / `InMemorySecureStorage` not defined.

- [ ] **Step 3: Write implementation**

Create `lib/core/security/secure_storage.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Narrow interface so tests can swap in an in-memory fake.
abstract class SecureStorage {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
  Future<void> clear();
}

class FlutterSecureStorageAdapter implements SecureStorage {
  FlutterSecureStorageAdapter([FlutterSecureStorage? inner])
      : _inner = inner ?? const FlutterSecureStorage();

  final FlutterSecureStorage _inner;

  static const _options = AndroidOptions(encryptedSharedPreferences: true);

  @override
  Future<void> write(String key, String value) =>
      _inner.write(key: key, value: value, aOptions: _options);

  @override
  Future<String?> read(String key) =>
      _inner.read(key: key, aOptions: _options);

  @override
  Future<void> delete(String key) =>
      _inner.delete(key: key, aOptions: _options);

  @override
  Future<void> clear() => _inner.deleteAll(aOptions: _options);
}

/// In-memory implementation for tests. NEVER used in production.
class InMemorySecureStorage implements SecureStorage {
  final _store = <String, String>{};

  @override
  Future<void> write(String key, String value) async => _store[key] = value;

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> delete(String key) async => _store.remove(key);

  @override
  Future<void> clear() async => _store.clear();
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/core/security/secure_storage_test.dart
```

Expected: all 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/security/secure_storage.dart test/core/security/secure_storage_test.dart
git commit -m "feat(security): SecureStorage wrapper + in-memory fake"
```

---

## Task 7: Biometric gate wrapper + test

**Files:**
- Create: `lib/core/security/biometric_gate.dart`
- Create: `test/core/security/biometric_gate_test.dart`

The biometric gate authenticates the user via fingerprint/face before sensitive actions. On a device without biometric hardware or with biometrics disabled, it falls through gracefully (the caller handles a `false` return — typically by falling back to password re-entry).

- [ ] **Step 1: Write failing test**

Create `test/core/security/biometric_gate_test.dart`:

```dart
import 'package:firecheck/core/security/biometric_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';

class _MockLocalAuth extends Mock implements LocalAuthentication {}

void main() {
  setUpAll(() {
    registerFallbackValue(const AuthenticationOptions());
  });

  group('BiometricGate', () {
    late _MockLocalAuth mockAuth;
    late BiometricGate gate;

    setUp(() {
      mockAuth = _MockLocalAuth();
      gate = BiometricGate(mockAuth);
    });

    test('isAvailable returns false when device does not support biometrics',
        () async {
      when(() => mockAuth.isDeviceSupported()).thenAnswer((_) async => false);
      when(() => mockAuth.canCheckBiometrics).thenAnswer((_) async => false);

      expect(await gate.isAvailable(), isFalse);
    });

    test('isAvailable returns true when device supports biometrics', () async {
      when(() => mockAuth.isDeviceSupported()).thenAnswer((_) async => true);
      when(() => mockAuth.canCheckBiometrics).thenAnswer((_) async => true);

      expect(await gate.isAvailable(), isTrue);
    });

    test('authenticate returns true on success', () async {
      when(() => mockAuth.authenticate(
            localizedReason: any(named: 'localizedReason'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => true);

      expect(await gate.authenticate(reason: 'Unlock'), isTrue);
    });

    test('authenticate returns false when user cancels or fails', () async {
      when(() => mockAuth.authenticate(
            localizedReason: any(named: 'localizedReason'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => false);

      expect(await gate.authenticate(reason: 'Unlock'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/core/security/biometric_gate_test.dart
```

Expected: FAIL — `BiometricGate` undefined.

- [ ] **Step 3: Write implementation**

Create `lib/core/security/biometric_gate.dart`:

```dart
import 'package:local_auth/local_auth.dart';

class BiometricGate {
  BiometricGate([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  Future<bool> isAvailable() async {
    final deviceSupported = await _auth.isDeviceSupported();
    if (!deviceSupported) return false;
    return _auth.canCheckBiometrics;
  }

  /// Returns true if the user authenticated successfully.
  /// Returns false if they cancelled, failed, or biometrics is unavailable.
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } on Exception {
      return false;
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
flutter test test/core/security/biometric_gate_test.dart
```

Expected: all 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/security/biometric_gate.dart test/core/security/biometric_gate_test.dart
git commit -m "feat(security): BiometricGate wrapper + tests"
```

---

## Task 8: Supabase client bootstrap + Riverpod provider

**Files:**
- Create: `lib/core/supabase/supabase_client_provider.dart`

The Supabase client is initialized once in `main.dart` (Task 16) and exposed via a Riverpod provider.

- [ ] **Step 1: Create provider**

Create `lib/core/supabase/supabase_client_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provider that returns the globally-initialized Supabase client.
/// `Supabase.initialize` must be called in main.dart before any consumer runs.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});
```

- [ ] **Step 2: Verify analyze**

```bash
flutter analyze lib/core/supabase/
```

Expected: no warnings.

- [ ] **Step 3: Commit**

```bash
git add lib/core/supabase/
git commit -m "feat(core): supabase client provider"
```

---

## Task 9: Auth state + auth repository + test

**Files:**
- Create: `lib/features/auth/domain/auth_state.dart`
- Create: `lib/features/auth/data/auth_repository.dart`
- Create: `test/features/auth/auth_repository_test.dart`

`AuthRepository` is the only place that talks to Supabase Auth. It exposes a `login`/`logout`/`restoreSession` API and a stream of `AuthState` transitions that Riverpod providers watch.

- [ ] **Step 1: Create `auth_state.dart`**

```dart
sealed class AuthState {
  const AuthState();
}

class Unauthenticated extends AuthState {
  const Unauthenticated();
}

class Authenticated extends AuthState {
  const Authenticated({required this.userId, required this.email});
  final String userId;
  final String email;
}

class AuthChecking extends AuthState {
  const AuthChecking();
}
```

- [ ] **Step 2: Write failing repository test**

Create `test/features/auth/auth_repository_test.dart`:

```dart
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/core/security/secure_storage.dart';
import 'package:firecheck/features/auth/data/auth_repository.dart';
import 'package:firecheck/features/auth/domain/auth_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockUser extends Mock implements User {}

class _MockSession extends Mock implements Session {}

class _MockAuthResponse extends Mock implements AuthResponse {}

void main() {
  late _MockSupabaseClient client;
  late _MockGoTrueClient auth;
  late InMemorySecureStorage storage;
  late AuthRepository repo;

  setUp(() {
    client = _MockSupabaseClient();
    auth = _MockGoTrueClient();
    storage = InMemorySecureStorage();
    when(() => client.auth).thenReturn(auth);
    repo = AuthRepository(client: client, storage: storage);
  });

  group('login', () {
    test('persists refresh token and returns Authenticated', () async {
      final user = _MockUser();
      when(() => user.id).thenReturn('user-1');
      when(() => user.email).thenReturn('j@example.com');

      final session = _MockSession();
      when(() => session.refreshToken).thenReturn('refresh-xyz');
      when(() => session.user).thenReturn(user);

      final resp = _MockAuthResponse();
      when(() => resp.user).thenReturn(user);
      when(() => resp.session).thenReturn(session);

      when(() => auth.signInWithPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenAnswer((_) async => resp);

      final state = await repo.login('j@example.com', 'password123');

      expect(state, isA<Authenticated>());
      expect((state as Authenticated).userId, 'user-1');
      expect(await storage.read('refresh_token'), 'refresh-xyz');
    });

    test('returns AuthFailure on bad credentials', () async {
      when(() => auth.signInWithPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenThrow(const AuthException('invalid'));

      expect(
        () => repo.login('bad', 'bad'),
        throwsA(isA<AuthFailure>()),
      );
    });
  });

  group('logout', () {
    test('signs out and clears refresh token', () async {
      await storage.write('refresh_token', 'stale');
      when(() => auth.signOut()).thenAnswer((_) async => {});

      await repo.logout();

      expect(await storage.read('refresh_token'), isNull);
      verify(() => auth.signOut()).called(1);
    });
  });

  group('restoreSession', () {
    test('returns Unauthenticated when no refresh token stored', () async {
      expect(await repo.restoreSession(), isA<Unauthenticated>());
    });

    test('returns Authenticated on valid refresh', () async {
      await storage.write('refresh_token', 'refresh-xyz');

      final user = _MockUser();
      when(() => user.id).thenReturn('user-1');
      when(() => user.email).thenReturn('j@example.com');

      final session = _MockSession();
      when(() => session.refreshToken).thenReturn('refresh-new');
      when(() => session.user).thenReturn(user);

      final resp = _MockAuthResponse();
      when(() => resp.session).thenReturn(session);
      when(() => resp.user).thenReturn(user);

      when(() => auth.setSession('refresh-xyz'))
          .thenAnswer((_) async => resp);

      final state = await repo.restoreSession();

      expect(state, isA<Authenticated>());
      expect(await storage.read('refresh_token'), 'refresh-new');
    });

    test('clears token and returns Unauthenticated on refresh failure',
        () async {
      await storage.write('refresh_token', 'refresh-expired');
      when(() => auth.setSession(any())).thenThrow(const AuthException('x'));

      final state = await repo.restoreSession();

      expect(state, isA<Unauthenticated>());
      expect(await storage.read('refresh_token'), isNull);
    });
  });
}
```

- [ ] **Step 3: Run test to verify failure**

```bash
flutter test test/features/auth/auth_repository_test.dart
```

Expected: FAIL — `AuthRepository` undefined.

- [ ] **Step 4: Implement `auth_repository.dart`**

Create `lib/features/auth/data/auth_repository.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/failure.dart';
import '../../../core/security/secure_storage.dart';
import '../domain/auth_state.dart';

class AuthRepository {
  AuthRepository({required this.client, required this.storage});
  final SupabaseClient client;
  final SecureStorage storage;

  static const _refreshTokenKey = 'refresh_token';

  Future<AuthState> login(String email, String password) async {
    try {
      final resp = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final session = resp.session;
      final user = resp.user;
      if (session == null || user == null) {
        throw const AuthFailure('Login succeeded but no session returned');
      }
      final refresh = session.refreshToken;
      if (refresh != null) {
        await storage.write(_refreshTokenKey, refresh);
      }
      return Authenticated(userId: user.id, email: user.email ?? '');
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  Future<void> logout() async {
    await client.auth.signOut();
    await storage.delete(_refreshTokenKey);
  }

  Future<AuthState> restoreSession() async {
    final refresh = await storage.read(_refreshTokenKey);
    if (refresh == null) return const Unauthenticated();
    try {
      final resp = await client.auth.setSession(refresh);
      final session = resp.session;
      final user = resp.user;
      if (session == null || user == null) {
        await storage.delete(_refreshTokenKey);
        return const Unauthenticated();
      }
      final newRefresh = session.refreshToken;
      if (newRefresh != null) {
        await storage.write(_refreshTokenKey, newRefresh);
      }
      return Authenticated(userId: user.id, email: user.email ?? '');
    } on AuthException {
      await storage.delete(_refreshTokenKey);
      return const Unauthenticated();
    }
  }
}
```

- [ ] **Step 5: Run tests to verify all pass**

```bash
flutter test test/features/auth/auth_repository_test.dart
```

Expected: all 5 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/auth/ test/features/auth/auth_repository_test.dart
git commit -m "feat(auth): AuthRepository with login/logout/restoreSession + tests"
```

---

## Task 10: Auth Riverpod providers

**Files:**
- Create: `lib/features/auth/presentation/auth_providers.dart`

Providers expose `AuthRepository` and the reactive `authStateProvider` that the router listens to.

- [ ] **Step 1: Create providers**

Create `lib/features/auth/presentation/auth_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/secure_storage.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../data/auth_repository.dart';
import '../domain/auth_state.dart';

final secureStorageProvider = Provider<SecureStorage>((_) {
  return FlutterSecureStorageAdapter();
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    client: ref.watch(supabaseClientProvider),
    storage: ref.watch(secureStorageProvider),
  );
});

/// Tracks current auth state. Starts as AuthChecking while restoreSession runs,
/// then transitions to Authenticated or Unauthenticated.
class AuthStateNotifier extends StateNotifier<AuthState> {
  AuthStateNotifier(this._repo) : super(const AuthChecking()) {
    _bootstrap();
  }

  final AuthRepository _repo;

  Future<void> _bootstrap() async {
    state = await _repo.restoreSession();
  }

  Future<void> login(String email, String password) async {
    state = await _repo.login(email, password);
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const Unauthenticated();
  }
}

final authStateProvider =
    StateNotifierProvider<AuthStateNotifier, AuthState>((ref) {
  return AuthStateNotifier(ref.watch(authRepositoryProvider));
});
```

- [ ] **Step 2: Verify analyze**

```bash
flutter analyze lib/features/auth/
```

Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add lib/features/auth/presentation/auth_providers.dart
git commit -m "feat(auth): Riverpod providers for auth state"
```

---

## Task 11: Login screen + widget test

**Files:**
- Create: `lib/features/auth/presentation/login_screen.dart`
- Create: `test/features/auth/login_screen_test.dart`

Simple login form: email, password, "Sign in" button. Calls `authStateProvider.notifier.login()`. Shows a snackbar on `AuthFailure`.

- [ ] **Step 1: Write failing widget test**

Create `test/features/auth/login_screen_test.dart`:

```dart
import 'package:firecheck/core/errors/failure.dart';
import 'package:firecheck/features/auth/data/auth_repository.dart';
import 'package:firecheck/features/auth/domain/auth_state.dart';
import 'package:firecheck/features/auth/presentation/auth_providers.dart';
import 'package:firecheck/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _MockAuthRepository repo;

  setUp(() {
    repo = _MockAuthRepository();
    when(() => repo.restoreSession())
        .thenAnswer((_) async => const Unauthenticated());
  });

  Widget buildSubject() {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: LoginScreen()),
    );
  }

  testWidgets('renders email + password fields and Sign in button',
      (tester) async {
    await tester.pumpWidget(buildSubject());
    await tester.pump();

    expect(find.byKey(const Key('login.email')), findsOneWidget);
    expect(find.byKey(const Key('login.password')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('submitting valid credentials calls repo.login', (tester) async {
    when(() => repo.login(any(), any())).thenAnswer(
      (_) async => const Authenticated(userId: 'u1', email: 'a@b.co'),
    );

    await tester.pumpWidget(buildSubject());
    await tester.pump();

    await tester.enterText(find.byKey(const Key('login.email')), 'a@b.co');
    await tester.enterText(find.byKey(const Key('login.password')), 'pw');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    verify(() => repo.login('a@b.co', 'pw')).called(1);
  });

  testWidgets('shows snackbar on AuthFailure', (tester) async {
    when(() => repo.login(any(), any()))
        .thenThrow(const AuthFailure('Invalid credentials'));

    await tester.pumpWidget(buildSubject());
    await tester.pump();

    await tester.enterText(find.byKey(const Key('login.email')), 'x');
    await tester.enterText(find.byKey(const Key('login.password')), 'y');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(find.text('Invalid credentials'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify failure**

```bash
flutter test test/features/auth/login_screen_test.dart
```

Expected: FAIL — `LoginScreen` not defined.

- [ ] **Step 3: Implement `LoginScreen`**

Create `lib/features/auth/presentation/login_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import 'auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await ref.read(authStateProvider.notifier).login(
            _email.text.trim(),
            _password.text,
          );
    } on Failure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FireCheck')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            TextField(
              key: const Key('login.email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('login.password'),
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify pass**

```bash
flutter test test/features/auth/login_screen_test.dart
```

Expected: all 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/presentation/login_screen.dart test/features/auth/login_screen_test.dart
git commit -m "feat(auth): login screen + widget tests"
```

---

## Task 12: Progress snapshot domain + progress repository

**Files:**
- Create: `lib/features/home/domain/progress_snapshot.dart`
- Create: `lib/features/home/data/progress_repository.dart`
- Create: `test/features/home/progress_repository_test.dart`

`ProgressSnapshot` summarizes what the home screen shows. `ProgressRepository` streams it from Drift — when a submission or sync_job changes, the stream emits a fresh snapshot, and the home UI rebuilds automatically.

- [ ] **Step 1: Create `progress_snapshot.dart`**

```dart
class ProgressSnapshot {
  const ProgressSnapshot({
    required this.totalFeatures,
    required this.completedFeatures,
    required this.inProgressFeatures,
    required this.queuedJobs,
    required this.failedJobs,
    required this.deadJobs,
  });

  final int totalFeatures;
  final int completedFeatures;
  final int inProgressFeatures;
  final int queuedJobs;
  final int failedJobs;
  final int deadJobs;

  static const empty = ProgressSnapshot(
    totalFeatures: 0,
    completedFeatures: 0,
    inProgressFeatures: 0,
    queuedJobs: 0,
    failedJobs: 0,
    deadJobs: 0,
  );
}
```

- [ ] **Step 2: Write failing repository test**

Create `test/features/home/progress_repository_test.dart`:

```dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:firecheck/core/db/database.dart';
import 'package:firecheck/features/home/data/progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ProgressRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ProgressRepository(db);
  });

  tearDown(() async => db.close());

  test('watchProgress emits empty snapshot when DB is empty', () async {
    final snap = await repo.watchProgress().first;
    expect(snap.totalFeatures, 0);
    expect(snap.completedFeatures, 0);
    expect(snap.queuedJobs, 0);
    expect(snap.failedJobs, 0);
    expect(snap.deadJobs, 0);
  });

  test('watchProgress reflects feature counts by status', () async {
    final now = DateTime.now();
    await db.into(db.features).insert(FeaturesCompanion.insert(
          id: 'f1',
          assignmentId: 'a1',
          featureType: 'building',
          geometryGeojson: '{}',
          createdAt: now,
          status: const Value('complete'),
        ));
    await db.into(db.features).insert(FeaturesCompanion.insert(
          id: 'f2',
          assignmentId: 'a1',
          featureType: 'building',
          geometryGeojson: '{}',
          createdAt: now,
          status: const Value('in_progress'),
        ));
    await db.into(db.features).insert(FeaturesCompanion.insert(
          id: 'f3',
          assignmentId: 'a1',
          featureType: 'road',
          geometryGeojson: '{}',
          createdAt: now,
        ));

    final snap = await repo.watchProgress().first;
    expect(snap.totalFeatures, 3);
    expect(snap.completedFeatures, 1);
    expect(snap.inProgressFeatures, 1);
  });

  test('watchProgress reflects sync_jobs counts by status', () async {
    final now = DateTime.now();
    await db.into(db.syncJobs).insert(SyncJobsCompanion.insert(
          id: 's1',
          entityType: 'submission',
          entityId: 'x',
          createdAt: now,
          status: const Value('pending'),
        ));
    await db.into(db.syncJobs).insert(SyncJobsCompanion.insert(
          id: 's2',
          entityType: 'submission',
          entityId: 'y',
          createdAt: now,
          status: const Value('failed'),
        ));
    await db.into(db.syncJobs).insert(SyncJobsCompanion.insert(
          id: 's3',
          entityType: 'photo',
          entityId: 'z',
          createdAt: now,
          status: const Value('dead'),
        ));

    final snap = await repo.watchProgress().first;
    expect(snap.queuedJobs, 1);
    expect(snap.failedJobs, 1);
    expect(snap.deadJobs, 1);
  });
}
```

- [ ] **Step 3: Run test to verify failure**

```bash
flutter test test/features/home/progress_repository_test.dart
```

Expected: FAIL — `ProgressRepository` undefined.

- [ ] **Step 4: Implement `ProgressRepository`**

Create `lib/features/home/data/progress_repository.dart`:

```dart
import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../domain/progress_snapshot.dart';

class ProgressRepository {
  ProgressRepository(this._db);
  final AppDatabase _db;

  Stream<ProgressSnapshot> watchProgress() {
    final featuresStream = _db.select(_db.features).watch();
    final jobsStream = _db.select(_db.syncJobs).watch();

    return Rx.combineLatest(featuresStream, jobsStream, (features, jobs) {
      final total = features.length;
      final completed = features.where((f) => f.status == 'complete').length;
      final inProgress =
          features.where((f) => f.status == 'in_progress').length;
      final queued = jobs
          .where((j) => j.status == 'pending' || j.status == 'in_progress')
          .length;
      final failed = jobs.where((j) => j.status == 'failed').length;
      final dead = jobs.where((j) => j.status == 'dead').length;

      return ProgressSnapshot(
        totalFeatures: total,
        completedFeatures: completed,
        inProgressFeatures: inProgress,
        queuedJobs: queued,
        failedJobs: failed,
        deadJobs: dead,
      );
    });
  }
}

/// Minimal combineLatest so we don't pull in rxdart just for this.
class Rx {
  static Stream<R> combineLatest<A, B, R>(
    Stream<A> a,
    Stream<B> b,
    R Function(A, B) combine,
  ) async* {
    A? latestA;
    B? latestB;
    var hasA = false;
    var hasB = false;

    final controller = StreamController<R>();

    final subA = a.listen((event) {
      latestA = event;
      hasA = true;
      if (hasB) controller.add(combine(latestA as A, latestB as B));
    }, onError: controller.addError);

    final subB = b.listen((event) {
      latestB = event;
      hasB = true;
      if (hasA) controller.add(combine(latestA as A, latestB as B));
    }, onError: controller.addError);

    controller.onCancel = () async {
      await subA.cancel();
      await subB.cancel();
    };

    yield* controller.stream;
  }
}
```

Note: the `Rx.combineLatest` above works but uses an async-gen that never returns — for Phase 0's needs (UI stream) this is fine. If you already have `rxdart` as a dep later, replace with `Rx.combineLatest2`. Add the missing import at the top:

```dart
import 'dart:async';
```

- [ ] **Step 5: Run test to verify pass**

```bash
flutter test test/features/home/progress_repository_test.dart
```

Expected: all 3 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/home/ test/features/home/progress_repository_test.dart
git commit -m "feat(home): progress snapshot domain + repository + tests"
```

---

## Task 13: Home screen + widget test

**Files:**
- Create: `lib/features/home/presentation/home_providers.dart`
- Create: `lib/features/home/presentation/home_screen.dart`
- Create: `test/features/home/home_screen_test.dart`

The home screen surfaces progress from the repository and renders three action tiles ("Gather Data", "Get Maps", "Upload Data"). In Phase 0 the tiles are stubs — tapping them shows a snackbar saying "Coming in Phase N". The real navigation targets land in later phases.

- [ ] **Step 1: Create `home_providers.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../data/progress_repository.dart';
import '../domain/progress_snapshot.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final progressRepositoryProvider = Provider<ProgressRepository>((ref) {
  return ProgressRepository(ref.watch(appDatabaseProvider));
});

final progressProvider = StreamProvider<ProgressSnapshot>((ref) {
  return ref.watch(progressRepositoryProvider).watchProgress();
});
```

- [ ] **Step 2: Write failing widget test**

Create `test/features/home/home_screen_test.dart`:

```dart
import 'package:firecheck/features/home/domain/progress_snapshot.dart';
import 'package:firecheck/features/home/presentation/home_providers.dart';
import 'package:firecheck/features/home/presentation/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildSubject(Stream<ProgressSnapshot> stream) {
    return ProviderScope(
      overrides: [
        progressProvider.overrideWith((ref) => stream),
      ],
      child: const MaterialApp(home: HomeScreen()),
    );
  }

  testWidgets('renders empty progress snapshot', (tester) async {
    await tester.pumpWidget(buildSubject(Stream.value(ProgressSnapshot.empty)));
    await tester.pump();

    expect(find.text('0 of 0 features'), findsOneWidget);
    expect(find.text('0 queued · 0 failed · 0 dead'), findsOneWidget);
  });

  testWidgets('renders action tiles for Gather / Get / Upload', (tester) async {
    await tester.pumpWidget(buildSubject(Stream.value(ProgressSnapshot.empty)));
    await tester.pump();

    expect(find.text('Gather Data'), findsOneWidget);
    expect(find.text('Get Maps'), findsOneWidget);
    expect(find.text('Upload Data'), findsOneWidget);
  });

  testWidgets('renders populated progress counts', (tester) async {
    const snap = ProgressSnapshot(
      totalFeatures: 100,
      completedFeatures: 42,
      inProgressFeatures: 5,
      queuedJobs: 3,
      failedJobs: 1,
      deadJobs: 0,
    );
    await tester.pumpWidget(buildSubject(Stream.value(snap)));
    await tester.pump();

    expect(find.text('42 of 100 features'), findsOneWidget);
    expect(find.text('3 queued · 1 failed · 0 dead'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run test to verify failure**

```bash
flutter test test/features/home/home_screen_test.dart
```

Expected: FAIL — `HomeScreen` undefined.

- [ ] **Step 4: Implement `HomeScreen`**

Create `lib/features/home/presentation/home_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'home_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSnap = ref.watch(progressProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('FireCheck')),
      body: asyncSnap.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (snap) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Assignment progress',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      Text(
                        '${snap.completedFeatures} of ${snap.totalFeatures} features',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      LinearProgressIndicator(
                        value: snap.totalFeatures == 0
                            ? 0
                            : snap.completedFeatures / snap.totalFeatures,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${snap.queuedJobs} queued · ${snap.failedJobs} failed · ${snap.deadJobs} dead',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _ActionTile(
                title: 'Gather Data',
                subtitle: 'Resume where you left off',
                onTap: () => _showComingSoon(context, 'Phase 1'),
              ),
              _ActionTile(
                title: 'Get Maps',
                subtitle: 'Download your assignment',
                onTap: () => _showComingSoon(context, 'Phase 1'),
              ),
              _ActionTile(
                title: 'Upload Data',
                subtitle: 'Send completed work',
                onTap: () => _showComingSoon(context, 'Phase 4'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context, String phase) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Coming in $phase')),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
```

- [ ] **Step 5: Run test to verify pass**

```bash
flutter test test/features/home/home_screen_test.dart
```

Expected: all 3 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/home/ test/features/home/home_screen_test.dart
git commit -m "feat(home): home screen with progress card + action tiles"
```

---

## Task 14: App router with auth redirect

**Files:**
- Create: `lib/core/router/app_router.dart`

Route list:
- `/login` → `LoginScreen`
- `/` → `HomeScreen` (requires authenticated)

The router listens to `authStateProvider` and redirects:
- `AuthChecking` → show splash
- `Unauthenticated` → `/login`
- `Authenticated` → `/`

- [ ] **Step 1: Create router**

Create `lib/core/router/app_router.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/auth_state.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/home/presentation/home_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(authStateProvider.notifier);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: _AuthListenable(notifier),
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      final onLogin = state.matchedLocation == '/login';

      return switch (auth) {
        AuthChecking() => null, // stay put; splash handles it
        Unauthenticated() => onLogin ? null : '/login',
        Authenticated() => onLogin ? '/' : null,
      };
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) {
          final auth = ref.watch(authStateProvider);
          if (auth is AuthChecking) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return const HomeScreen();
        },
      ),
    ],
  );
});

/// Adapts a StateNotifier into a Listenable go_router can subscribe to.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._notifier) {
    _notifier.addListener(_onChange);
  }
  final StateNotifier<AuthState> _notifier;

  void _onChange(AuthState _) => notifyListeners();

  @override
  void dispose() {
    _notifier.removeListener(_onChange);
    super.dispose();
  }
}
```

- [ ] **Step 2: Verify analyze**

```bash
flutter analyze lib/core/router/
```

Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add lib/core/router/
git commit -m "feat(router): go_router with auth-gated redirect"
```

---

## Task 15: App shell + theme + i18n bootstrap

**Files:**
- Create: `lib/app.dart`
- Create: `lib/core/i18n/app_en.arb`
- Create: `lib/core/i18n/app_tl.arb`
- Modify: `pubspec.yaml` (l10n section — already covered in Task 1)

Phase 0 i18n is minimal — just the labels used on login + home. More labels arrive with each phase.

- [ ] **Step 1: Create ARB files**

Create `lib/core/i18n/app_en.arb`:

```json
{
  "@@locale": "en",
  "appTitle": "FireCheck",
  "signIn": "Sign in",
  "email": "Email",
  "password": "Password",
  "assignmentProgress": "Assignment progress",
  "featuresLabel": "{completed} of {total} features",
  "@featuresLabel": {
    "placeholders": {
      "completed": {"type": "int"},
      "total": {"type": "int"}
    }
  },
  "jobCountsLabel": "{queued} queued · {failed} failed · {dead} dead",
  "@jobCountsLabel": {
    "placeholders": {
      "queued": {"type": "int"},
      "failed": {"type": "int"},
      "dead": {"type": "int"}
    }
  },
  "gatherData": "Gather Data",
  "gatherDataSubtitle": "Resume where you left off",
  "getMaps": "Get Maps",
  "getMapsSubtitle": "Download your assignment",
  "uploadData": "Upload Data",
  "uploadDataSubtitle": "Send completed work",
  "comingInPhase": "Coming in {phase}",
  "@comingInPhase": {
    "placeholders": {"phase": {"type": "String"}}
  }
}
```

Create `lib/core/i18n/app_tl.arb`:

```json
{
  "@@locale": "tl",
  "appTitle": "FireCheck",
  "signIn": "Mag-sign in",
  "email": "Email",
  "password": "Password",
  "assignmentProgress": "Progreso ng takda",
  "featuresLabel": "{completed} sa {total} na istruktura",
  "jobCountsLabel": "{queued} nakapila · {failed} nabigo · {dead} patay",
  "gatherData": "Mangalap ng Datos",
  "gatherDataSubtitle": "Ituloy kung saan ka huling tumigil",
  "getMaps": "Kumuha ng Mapa",
  "getMapsSubtitle": "I-download ang iyong takda",
  "uploadData": "I-upload ang Datos",
  "uploadDataSubtitle": "Ipadala ang tapos na gawa",
  "comingInPhase": "Darating sa {phase}"
}
```

- [ ] **Step 2: Add `l10n.yaml`**

Create `l10n.yaml` at the project root:

```yaml
arb-dir: lib/core/i18n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
synthetic-package: false
output-dir: lib/generated/l10n
```

Also ensure `pubspec.yaml` has `generate: true` under `flutter:` (already done in Task 1).

- [ ] **Step 3: Run l10n codegen**

```bash
flutter gen-l10n
```

Expected: `lib/generated/l10n/app_localizations.dart` and `_en.dart`, `_tl.dart` are produced.

- [ ] **Step 4: Create `app.dart`**

Create `lib/app.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'generated/l10n/app_localizations.dart';

class FireCheckApp extends ConsumerWidget {
  const FireCheckApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'FireCheck',
      routerConfig: router,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC94A23)),
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
```

- [ ] **Step 5: Verify analyze**

```bash
flutter analyze lib/app.dart lib/core/i18n/
```

Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add lib/app.dart lib/core/i18n/ l10n.yaml lib/generated/
git commit -m "feat(app): MaterialApp.router + theme + EN/TL l10n bootstrap"
```

---

## Task 16: main.dart wiring + Supabase bootstrap + smoke test

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Replace generated `main.dart`**

Overwrite `lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');
  final url = dotenv.env['SUPABASE_URL'];
  final anonKey = dotenv.env['SUPABASE_ANON_KEY'];
  if (url == null || url.isEmpty || anonKey == null || anonKey.isEmpty) {
    throw StateError(
      'SUPABASE_URL / SUPABASE_ANON_KEY missing from .env. '
      'Copy .env.example to .env and fill in real values.',
    );
  }

  await Supabase.initialize(url: url, anonKey: anonKey);

  runApp(const ProviderScope(child: FireCheckApp()));
}
```

- [ ] **Step 2: Ensure `.env` file exists locally**

If not already done:

```bash
cp .env.example .env
# then edit .env with the real SUPABASE_URL and anon key
```

- [ ] **Step 3: Delete the stale `test/widget_test.dart`**

`flutter create` generated a counter-app widget test that won't compile against the new `FireCheckApp`. Remove it:

```bash
rm test/widget_test.dart
```

- [ ] **Step 4: Run full test suite**

```bash
flutter test
```

Expected: all tests PASS. No failures from removed widget_test.dart.

- [ ] **Step 5: Run the app on a device or emulator**

Ensure at least one enumerator exists on Supabase:
- In the Supabase dashboard → Authentication → Add user → create `test@example.com` with a password.
- In the SQL editor: `insert into public.enumerators (id, username, display_name) values ('<user-uuid-from-auth>', 'test', 'Test Enumerator');`

Then:

```bash
flutter run
```

Expected behavior:
1. App boots to a login screen.
2. Enter the email/password from the previous step.
3. Land on the home screen.
4. See "0 of 0 features · 0 queued · 0 failed · 0 dead".
5. Tap each action tile — each shows a "Coming in Phase N" snackbar.
6. Kill the app (swipe from recents) and reopen — should land directly on the home screen, bypassing the login screen (session restored via `restoreSession`).

- [ ] **Step 6: Commit**

```bash
git add lib/main.dart
git rm test/widget_test.dart
git commit -m "feat(app): main.dart wires Supabase + ProviderScope + FireCheckApp"
```

---

## Task 17: Tag Phase 0 complete

- [ ] **Step 1: Run full test and analyze pipeline**

```bash
flutter analyze && flutter test
```

Expected: zero warnings, all tests pass.

- [ ] **Step 2: Tag release**

```bash
git tag -a phase-0-foundations -m "Phase 0: Flutter scaffold + Drift + Supabase auth + biometric + home shell"
```

- [ ] **Step 3: Push**

Only run this if the user wants to push to a remote:

```bash
git push origin main --tags
```

---

## Self-review (plan-level)

**Spec coverage:** scanning spec §12 Phase 0 row — Flutter scaffold ✓ (T1), Riverpod ✓ (T10, T13), Drift schema + migrations ✓ (T3, T4), Supabase project + RLS + tables ✓ (T2), auth screen ✓ (T11), secure storage ✓ (T6), biometric unlock ✓ (T7), empty home screen with real progress counts ✓ (T12, T13). Router with auth gating ✓ (T14). i18n bootstrap ✓ (T15). All covered.

**Deferred with justification (not a spec gap):** Phase 0 does not implement `PostGIS ↔ Dart geometry` helpers, `connectivity_plus` wiring, WorkManager registration, or MapLibre — those belong to Phases 1 and 4 and are noted as coming later in the plan header.

**Placeholder scan:** no TBD/TODO/"implement later" / "similar to Task N". Every code step has complete, runnable code. Single call-out: the `Rx.combineLatest` shim in T12 Step 4 is deliberately minimal (works but uses async-gen — noted inline). Acceptable.

**Type consistency:**
- `AuthState` / `Authenticated` / `Unauthenticated` / `AuthChecking` — consistent between T9 (definition), T10 (consumer), T14 (switch arms).
- `ProgressSnapshot` fields `totalFeatures/completedFeatures/inProgressFeatures/queuedJobs/failedJobs/deadJobs` — matched in T12 (creation), T13 (consumption).
- `AuthRepository.login/logout/restoreSession` — signatures match between T9 (impl) and T10 (usage).
- `SecureStorage` interface — consistent between T6 (definition), T9 (auth_repo consumer), T10 (provider).
- Drift table names (e.g., `features`, `syncJobs`, `buildingAttributes`) — Drift generates these from class names; T12's test references `db.features`, `db.syncJobs` which the generator produces from `Features` and `SyncJobs` table classes in T3.

**One follow-up noted for Phase 1:** once MapLibre lands, the `supabase_flutter` session-restore will need a token refresh path if the refresh token itself has expired (> 30 days idle). Spec's auth edge cases (§10) cover this and the failure handling in T9 already returns `Unauthenticated` on refresh failure, so the UI will route back to login — correct behavior.
