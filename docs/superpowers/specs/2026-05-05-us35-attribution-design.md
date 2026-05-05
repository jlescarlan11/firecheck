# US-35: Google Sign-In Attribution Design

**Story:** As an enumerator, I want to sign in once with a Google account so that all subsequent downloads and uploads are attributed to me.

**Status:** Approved — implementation in progress  
**Branch:** `35-as-an-enumerator-i-want-to-sign-in-once-with-a-google-account-so-that-all-subsequent-downloads-and-uploads-are-attributed-to-me`

---

## Context

US-23/US-31 landed Google OAuth sign-in via Supabase. Three attribution gaps remain:

1. **P0 (broken prod):** `getEnumeratorId()` returns an email prefix string; the RPC casts it to `::uuid` → hard Postgres error on every submission upload
2. **P0 (prerequisite):** No trigger creates `enumerators` rows on first sign-in; FK target doesn't exist
3. **Download attribution:** `assignments.enumerator_id + downloaded_at` doesn't satisfy "all subsequent downloads" — can't detect re-downloads or per-file granularity
4. **Drive upload attribution:** Drive's native ownership via user OAuth token is sufficient — no custom `appProperties` needed *(out of scope by decision)*

---

## Architecture

### Sign-out

Verify that `signOut()` in `SupabaseGoogleAuthRepository` calls `supabase.auth.signOut()` and that GoRouter redirects unauthenticated users away from protected routes. If broken, fix in PR 1.

### Enumerator identity fix (PR 1)

`getEnumeratorId()` must return `supabase.auth.currentUser!.id` (the Supabase UUID), not the email prefix. Every call site must be updated — grep for `getEnumeratorId` and trace each.

### Trigger: `enumerators` row on sign-in (PR 1 — Migration 012)

```sql
create or replace function public.handle_new_enumerator()
returns trigger language plpgsql security definer set search_path = public
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

**Key decisions:**
- Inner `begin/exception` block logs but never re-raises — auth insert always succeeds
- `on conflict (id) do nothing` handles idempotency (e.g., re-trigger on schema drift)
- `username` has no unique constraint (confirmed) — email prefix collisions are allowed; `id` is the real PK

### Backfill: existing auth users (PR 1 — Migration 013, separate file)

```sql
insert into public.enumerators (id, username, display_name)
select
  id,
  split_part(email, '@', 1),
  coalesce(raw_user_meta_data->>'full_name', split_part(email, '@', 1))
from auth.users
on conflict (id) do nothing;
```

Separate migration so trigger is live before backfill runs. If backfill fails on bad data, new sign-ins are unaffected.

### Download events table (PR 2 — Migration 014)

```sql
create table public.download_events (
  id          uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments(id) on delete cascade,
  file_id     text not null,
  enumerator_id uuid not null references public.enumerators(id) on delete cascade,
  created_at  timestamptz not null default now()
);

create index download_events_enumerator_activity
  on public.download_events (enumerator_id, created_at desc);
```

- `file_id`: Drive file ID — assignments can contain multiple files; per-file granularity required
- `created_at` (not `downloaded_at`) — consistent with schema convention
- Index supports "recent activity" queries by enumerator

Write path: on successful shapefile import, insert one row per downloaded Drive file.

---

## PR Plan

| PR | Contents | State |
|----|----------|-------|
| PR 1 | Migration 012 (trigger), Migration 013 (backfill), `getEnumeratorId()` UUID fix, sign-out verification, extended submission tests | Ship today |
| PR 2 | Migration 014 (`download_events` table + index), write path in shapefile importer | Draft — schema review first |

---

## Out of Scope

- Drive file `appProperties` with enumerator UUID: Drive's native ownership via user OAuth token is the source of truth. No downstream consumer needs UUID-on-file. Decided out of scope to avoid duplicating data Google already records.
- Generic audit log table: out of scope for this story; B (lightweight `download_events`) covers the story's "all subsequent downloads" requirement.

---

## Acceptance Criteria

1. Fresh sign-in creates an `enumerators` row; submission upload succeeds with correct UUID in `submitted_by`
2. Sign-in auth always succeeds even if `enumerators` insert fails
3. Sign-out clears the session; protected routes reject subsequent requests
4. Every shapefile download inserts a row in `download_events` with correct `enumerator_id`, `file_id`, and `created_at`
5. Existing submission tests cover the happy path with a real authenticated UUID (no orphan test file)
