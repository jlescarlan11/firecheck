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

create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_enumerator();
