-- supabase/migrations/013_enumerators_backfill.sql
-- One-time backfill: creates enumerators rows for any auth.users who signed in
-- before the 012 trigger landed. on conflict (id) do nothing makes it safe to
-- re-run. Skips phone/anonymous/service users (email IS NULL) to avoid a NULL
-- constraint violation on the username column.
insert into public.enumerators (id, username, display_name)
select
  id,
  split_part(email, '@', 1),
  coalesce(raw_user_meta_data->>'full_name', split_part(email, '@', 1))
from auth.users
where email is not null
on conflict (id) do nothing;
