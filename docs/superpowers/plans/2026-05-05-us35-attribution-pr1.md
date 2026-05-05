# US-35 Attribution — PR 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the broken enumerator identity chain — create `enumerators` rows on first sign-in and make `getEnumeratorId()` return the Supabase UUID so submissions stop throwing a Postgres cast error.

**Architecture:** Two new Supabase migrations (trigger + backfill in separate files) plus a one-line Dart fix in `getEnumeratorId()`. The trigger is wrapped in a try/catch so auth never fails if profile creation errors. The backfill ships as a separate migration so the trigger is live before it runs. Sign-out already works via the existing router redirect.

**Tech Stack:** Flutter, Riverpod, Drift (local SQLite), Supabase (Postgres), GoRouter, mocktail (tests)

---

## File Map

| Action | File |
|--------|------|
| Create | `supabase/migrations/012_enumerators_trigger.sql` |
| Create | `supabase/migrations/013_enumerators_backfill.sql` |
| Modify | `lib/features/auth/data/supabase_google_auth_repository.dart` (line 31) |
| Modify | `lib/features/auth/data/fake_google_auth_repository.dart` (line 20) |
| Modify | `test/features/auth/supabase_google_auth_repository_test.dart` (lines 39–44) |
| Modify | `test/features/survey/building_form/submission_repository_test.dart` (extend) |
| Verify (no change) | `lib/core/router/app_router.dart` (sign-out redirect confirmed at line 34) |

---

## Task 1: Write Migration 012 — Enumerators Trigger

**Files:**
- Create: `supabase/migrations/012_enumerators_trigger.sql`

- [ ] **Step 1: Create the migration file**

```sql
-- supabase/migrations/012_enumerators_trigger.sql
-- Creates an enumerators profile row whenever a new user signs in via Supabase Auth.
-- The inner begin/exception block logs failures without re-raising, so auth inserts
-- always succeed even if profile creation errors (constraint violation, schema drift).
create or replace function public.handle_new_enumerator()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    insert into public.enumerators (id, username, display_name)
    values (
      new.id,
      split_part(new.email, '@', 1),
      coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1))
    )
    on conflict (id) do nothing;
  exception when others then
    raise warning 'handle_new_enumerator failed for user %: %', new.id, sqlerrm;
  end;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_enumerator();
```

- [ ] **Step 2: Verify the file was created**

```bash
cat "supabase/migrations/012_enumerators_trigger.sql"
```

Expected: full SQL content printed to terminal with no errors.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/012_enumerators_trigger.sql
git commit -m "feat(db): add trigger to create enumerators row on first sign-in (US-35)"
```

---

## Task 2: Write Migration 013 — Enumerators Backfill

**Files:**
- Create: `supabase/migrations/013_enumerators_backfill.sql`

Separate file from the trigger migration. If this backfill fails on bad data, the trigger (012) is already live, so new sign-ins keep working while the backfill is fixed.

- [ ] **Step 1: Create the migration file**

```sql
-- supabase/migrations/013_enumerators_backfill.sql
-- One-time backfill: creates enumerators rows for any auth.users who signed in
-- before the 012 trigger landed. on conflict (id) do nothing makes it safe to
-- re-run.
insert into public.enumerators (id, username, display_name)
select
  id,
  split_part(email, '@', 1),
  coalesce(raw_user_meta_data->>'full_name', split_part(email, '@', 1))
from auth.users
on conflict (id) do nothing;
```

- [ ] **Step 2: Verify the file was created**

```bash
cat "supabase/migrations/013_enumerators_backfill.sql"
```

Expected: full SQL content printed to terminal.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/013_enumerators_backfill.sql
git commit -m "feat(db): backfill enumerators for existing auth.users (US-35)"
```

---

## Task 3: Fix getEnumeratorId() — Return UUID Instead of Email Prefix (TDD)

**Files:**
- Modify: `test/features/auth/supabase_google_auth_repository_test.dart` (lines 39–44)
- Modify: `lib/features/auth/data/supabase_google_auth_repository.dart` (line 31)
- Modify: `lib/features/auth/data/fake_google_auth_repository.dart` (line 20)

The existing test at line 39–44 expects the email prefix (`'jlescarlan11'`). Update the test first so it fails, then fix the implementation, then verify it passes.

- [ ] **Step 1: Update the test to expect UUID**

In `test/features/auth/supabase_google_auth_repository_test.dart`, replace lines 38–51:

```dart
  group('getEnumeratorId', () {
    test('returns Supabase user UUID', () async {
      final user = _MockUser();
      when(() => auth.currentUser).thenReturn(user);
      when(() => user.id).thenReturn('550e8400-e29b-41d4-a716-446655440000');
      final repo = SupabaseGoogleAuthRepository(auth: auth);
      expect(
        await repo.getEnumeratorId(),
        '550e8400-e29b-41d4-a716-446655440000',
      );
    });

    test('throws AuthFailure when not signed in', () async {
      when(() => auth.currentUser).thenReturn(null);
      final repo = SupabaseGoogleAuthRepository(auth: auth);
      expect(repo.getEnumeratorId(), throwsA(isA<AuthFailure>()));
    });
  });
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/features/auth/supabase_google_auth_repository_test.dart --name "returns Supabase user UUID"
```

Expected: FAIL — `Expected: '550e8400-e29b-41d4-a716-446655440000'  Actual: 'jlescarlan11'`

- [ ] **Step 3: Fix getEnumeratorId() in the real repository**

In `lib/features/auth/data/supabase_google_auth_repository.dart`, replace lines 28–32:

```dart
  @override
  Future<String> getEnumeratorId() async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthFailure('Not signed in');
    return user.id;
  }
```

- [ ] **Step 4: Update the fake repository to return a UUID-shaped string**

In `lib/features/auth/data/fake_google_auth_repository.dart`, replace line 20:

```dart
  @override
  Future<String> getEnumeratorId() async =>
      '00000000-0000-0000-0000-000000000001';
```

- [ ] **Step 5: Run the updated test group to verify it passes**

```bash
flutter test test/features/auth/supabase_google_auth_repository_test.dart
```

Expected: All tests PASS (3 groups: isSignedIn, getEnumeratorId, getAccessToken).

- [ ] **Step 6: Commit**

```bash
git add lib/features/auth/data/supabase_google_auth_repository.dart \
        lib/features/auth/data/fake_google_auth_repository.dart \
        test/features/auth/supabase_google_auth_repository_test.dart
git commit -m "fix(auth): getEnumeratorId returns Supabase UUID instead of email prefix (US-35)"
```

---

## Task 4: Extend Submission Tests to Cover UUID Round-Trip

**Files:**
- Modify: `test/features/survey/building_form/submission_repository_test.dart`

The existing tests use `enumeratorId: 'u1'` (arbitrary string). Add one test that uses a proper UUID and verifies it round-trips through the local Drift DB intact. This is the regression guard the tech lead asked for — if `getEnumeratorId()` ever regresses back to a string, this test catches the mismatch before the RPC does.

- [ ] **Step 1: Write the failing test**

In `test/features/survey/building_form/submission_repository_test.dart`, add inside `main()` after the existing tests:

```dart
  test('ensureDraftForFeature stores UUID enumeratorId in submittedBy', () async {
    const uuid = '550e8400-e29b-41d4-a716-446655440000';
    final submission = await repo.ensureDraftForFeature(
      featureId: 'f1',
      enumeratorId: uuid,
    );
    expect(submission.submittedBy, uuid);
  });
```

- [ ] **Step 2: Run the test to verify it fails (or passes — both are informative)**

```bash
flutter test test/features/survey/building_form/submission_repository_test.dart --name "stores UUID enumeratorId"
```

Expected: PASS immediately (Drift stores TEXT as-is). If it fails, the `submittedBy` column has a type constraint we didn't know about — investigate before proceeding.

- [ ] **Step 3: Run the full submission test file**

```bash
flutter test test/features/survey/building_form/submission_repository_test.dart
```

Expected: All tests PASS.

- [ ] **Step 4: Commit**

```bash
git add test/features/survey/building_form/submission_repository_test.dart
git commit -m "test(submission): verify UUID enumeratorId round-trips through submittedBy (US-35)"
```

---

## Task 5: Verify Sign-Out (No Code Change Expected)

**Files:**
- Verify (no change): `lib/core/router/app_router.dart`
- Verify (no change): `lib/features/auth/data/supabase_google_auth_repository.dart`

Sign-out was implemented in US-23. Confirm it's still correct before opening PR 1.

- [ ] **Step 1: Confirm sign-out clears the session**

Open `lib/features/auth/data/supabase_google_auth_repository.dart` line 25:
```dart
Future<void> signOut() => _auth.signOut();
```
`_auth.signOut()` is Supabase's `GoTrueClient.signOut()`, which invalidates the session server-side and clears local storage. ✓

- [ ] **Step 2: Confirm the router redirects unauthenticated users**

Open `lib/core/router/app_router.dart` line 34:
```dart
if (session == null && !onSignIn) return '/sign-in';
```
`supabaseAuthStateProvider` emits `null` immediately after `signOut()` fires. `_SupabaseAuthListenable` at line 102 listens to `onAuthStateChange` and calls `notifyListeners()`, triggering GoRouter to re-evaluate the redirect. All protected routes redirect to `/sign-in`. ✓

- [ ] **Step 3: Note the verification in your PR description**

Add to the PR body:
> Sign-out: verified that `signOut()` delegates to Supabase `GoTrueClient.signOut()` and the router redirects all protected routes to `/sign-in` via `_SupabaseAuthListenable`. No code change needed — working correctly from US-23.

---

## Task 6: Full Test Suite + Open PR 1

- [ ] **Step 1: Run the full test suite**

```bash
flutter test
```

Expected: All tests PASS. If any test fails due to `'test-enumerator'` → UUID change in `FakeGoogleAuthRepository`, find the failing test, update the hardcoded string to `'00000000-0000-0000-0000-000000000001'`, and commit the fix before continuing.

- [ ] **Step 2: Run the analyzer**

```bash
dart analyze
```

Expected: Zero errors. Warnings and info messages are OK.

- [ ] **Step 3: Open PR 1**

```bash
gh pr create \
  --title "fix(us35): enumerator identity chain — trigger + UUID fix" \
  --body "$(cat <<'EOF'
## What

Fixes the broken enumerator identity chain that caused every submission upload to fail with a Postgres UUID cast error.

## Changes

- **Migration 012:** Postgres trigger on `auth.users` insert creates a row in `public.enumerators`. Inner `begin/exception` block logs failures without re-raising — auth always succeeds.
- **Migration 013:** One-time backfill for existing `auth.users` who signed in before the trigger landed. Separate migration so the trigger is live before the backfill runs.
- **`getEnumeratorId()`:** Now returns `user.id` (Supabase UUID) instead of the email local-part. All call sites receive the correct type for the `submitted_by` UUID FK.
- **`FakeGoogleAuthRepository`:** Returns a UUID-shaped string to stay consistent with the real implementation.
- **Submission tests:** Extended to verify UUID `enumeratorId` round-trips through `submittedBy`.

## Sign-out

Verified that `signOut()` delegates to Supabase `GoTrueClient.signOut()` and the router redirects all protected routes to `/sign-in` via `_SupabaseAuthListenable`. No code change needed — working correctly from US-23.

## Drive upload attribution (Gap 3)

Not implemented. Drive's native ownership via the user's own OAuth token is the source of truth for upload attribution. No downstream consumer needs the enumerator UUID on the file itself. Decided out of scope — see spec at `docs/superpowers/specs/2026-05-05-us35-attribution-design.md`.

## Test plan
- [ ] All existing tests pass (`flutter test`)
- [ ] Zero analyzer errors (`dart analyze`)
- [ ] Fresh sign-in creates an `enumerators` row in Supabase dashboard
- [ ] Submission upload succeeds (no UUID cast error)
- [ ] Sign-out redirects to sign-in screen; protected routes reject re-entry without sign-in

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Task 7: Create PR 2 Draft — download_events Schema

**Files:**
- Create: `supabase/migrations/014_download_events.sql`

PR 2 is draft-only at this stage. The tech lead reviews the schema before the write path is wired up.

- [ ] **Step 1: Create the migration file**

```sql
-- supabase/migrations/014_download_events.sql
-- Logs every shapefile download with per-file granularity.
-- file_id is the Drive file ID — assignments can contain multiple files.
-- Index on (enumerator_id, created_at desc) supports "recent activity" queries.
create table public.download_events (
  id            uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments(id) on delete cascade,
  file_id       text not null,
  enumerator_id uuid not null references public.enumerators(id) on delete cascade,
  created_at    timestamptz not null default now()
);

create index download_events_enumerator_activity
  on public.download_events (enumerator_id, created_at desc);
```

- [ ] **Step 2: Commit the migration**

```bash
git add supabase/migrations/014_download_events.sql
git commit -m "feat(db): add download_events table schema (US-35, draft for review)"
```

- [ ] **Step 3: Open PR 2 as draft**

```bash
gh pr create \
  --title "feat(us35): download_events table — schema draft" \
  --draft \
  --body "$(cat <<'EOF'
## What

Adds the `download_events` table to log per-file shapefile downloads attributed to the enumerator.

Schema only — write path not wired up yet. Requesting schema review before proceeding.

## Schema

```sql
create table public.download_events (
  id            uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments(id) on delete cascade,
  file_id       text not null,
  enumerator_id uuid not null references public.enumerators(id) on delete cascade,
  created_at    timestamptz not null default now()
);

create index download_events_enumerator_activity
  on public.download_events (enumerator_id, created_at desc);
```

## Questions for reviewer

- Is `file_id text` the right type for the Drive file ID, or do we want a length constraint?
- Should `assignment_id` cascade delete, or set null (preserve history if assignment is deleted)?

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
