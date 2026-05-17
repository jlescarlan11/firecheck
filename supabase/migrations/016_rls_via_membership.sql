-- supabase/migrations/016_rls_via_membership.sql
-- Replaces single-owner RLS checks with assignment_members lookups.
-- Touched tables: assignments, features, submissions, building_attributes,
-- road_attributes, household_surveys, photos.

begin;

-- assignments: a user can see/upsert an assignment if they're a member.
drop policy if exists assignments_own_rw on public.assignments;
create policy assignments_member_rw on public.assignments
  for all
  using (
    exists (
      select 1 from public.assignment_members am
      where am.assignment_id = assignments.id
        and am.enumerator_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.assignment_members am
      where am.assignment_id = assignments.id
        and am.enumerator_id = auth.uid()
    )
  );

-- features: scoped by parent assignment membership.
drop policy if exists features_via_assignment_rw on public.features;
create policy features_via_membership_rw on public.features
  for all
  using (
    exists (
      select 1 from public.assignment_members am
      where am.assignment_id = features.assignment_id
        and am.enumerator_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.assignment_members am
      where am.assignment_id = features.assignment_id
        and am.enumerator_id = auth.uid()
    )
  );

-- submissions: scoped via features → assignment_members.
drop policy if exists submissions_via_feature_rw on public.submissions;
create policy submissions_via_membership_rw on public.submissions
  for all
  using (
    exists (
      select 1 from public.features f
      join public.assignment_members am on am.assignment_id = f.assignment_id
      where f.id = submissions.feature_id
        and am.enumerator_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.features f
      join public.assignment_members am on am.assignment_id = f.assignment_id
      where f.id = submissions.feature_id
        and am.enumerator_id = auth.uid()
    )
  );

-- building_attributes, road_attributes, household_surveys: scoped via submission → feature → membership.
drop policy if exists building_attrs_via_submission_rw on public.building_attributes;
create policy building_attrs_via_membership_rw on public.building_attributes
  for all
  using (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignment_members am on am.assignment_id = f.assignment_id
      where s.id = building_attributes.submission_id
        and am.enumerator_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignment_members am on am.assignment_id = f.assignment_id
      where s.id = building_attributes.submission_id
        and am.enumerator_id = auth.uid()
    )
  );

drop policy if exists road_attrs_via_submission_rw on public.road_attributes;
create policy road_attrs_via_membership_rw on public.road_attributes
  for all
  using (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignment_members am on am.assignment_id = f.assignment_id
      where s.id = road_attributes.submission_id
        and am.enumerator_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignment_members am on am.assignment_id = f.assignment_id
      where s.id = road_attributes.submission_id
        and am.enumerator_id = auth.uid()
    )
  );

drop policy if exists household_via_submission_rw on public.household_surveys;
create policy household_via_membership_rw on public.household_surveys
  for all
  using (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignment_members am on am.assignment_id = f.assignment_id
      where s.id = household_surveys.submission_id
        and am.enumerator_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignment_members am on am.assignment_id = f.assignment_id
      where s.id = household_surveys.submission_id
        and am.enumerator_id = auth.uid()
    )
  );

-- photos: scoped via submission → feature → membership.
drop policy if exists photos_via_submission_rw on public.photos;
create policy photos_via_membership_rw on public.photos
  for all
  using (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignment_members am on am.assignment_id = f.assignment_id
      where s.id = photos.submission_id
        and am.enumerator_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.submissions s
      join public.features f on f.id = s.feature_id
      join public.assignment_members am on am.assignment_id = f.assignment_id
      where s.id = photos.submission_id
        and am.enumerator_id = auth.uid()
    )
  );

commit;
