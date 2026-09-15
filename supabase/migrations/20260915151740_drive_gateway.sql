-- Additive migration. Cutover and legacy RPC revocation happen explicitly in
-- server/drive-gateway/sql/activate.sql after supervisors approve the roster.
begin;
create schema if not exists firecheck_gateway;
revoke all on schema firecheck_gateway from public, anon, authenticated;
create table firecheck_gateway.settings (id boolean primary key default true check(id), enabled boolean not null default false);
insert into firecheck_gateway.settings(id) values(true);
create table firecheck_gateway.supervisors (user_id uuid primary key references public.enumerators(id));
create table firecheck_gateway.sources (
 assignment_id uuid primary key references public.assignments(id), folder_id text not null unique,
 current_version uuid, registered_by uuid not null references public.enumerators(id)
);
create table firecheck_gateway.versions (
 id uuid primary key, assignment_id uuid not null references public.assignments(id),
 manifest jsonb not null, manifest_hash text not null, published_by uuid not null,
 published_at timestamptz not null default now()
);
create index on firecheck_gateway.versions(assignment_id);
alter table firecheck_gateway.sources add foreign key(current_version) references firecheck_gateway.versions(id);
create table firecheck_gateway.uploads (
 id uuid primary key, assignment_id uuid not null references public.assignments(id), user_id uuid not null references public.enumerators(id),
 manifest_hash text not null, folder_id text not null, folder_path text not null,
 complete boolean not null default false, completed_at timestamptz,
 created_at timestamptz not null default now()
);
create index on firecheck_gateway.uploads(user_id,assignment_id);
create table firecheck_gateway.upload_files (
 upload_id uuid not null references firecheck_gateway.uploads(id), id uuid not null,
 name text not null, size bigint not null check(size > 0), md5 text not null,
 drive_id text not null, resumable_url text, complete boolean not null default false,
 primary key(upload_id,id), unique(upload_id,name)
);
create table firecheck_gateway.events (
 id bigint generated always as identity primary key, actor uuid not null,
 action text not null, assignment_id uuid, details jsonb not null default '{}', created_at timestamptz not null default now()
);
-- A non-login group role; grant it to a dedicated login at deployment. No app
-- user can access these tables through PostgREST or this role.
do $$ begin
 if not exists(select 1 from pg_roles where rolname='firecheck_gateway_server') then
   create role firecheck_gateway_server nologin;
 end if;
end $$;
grant usage on schema firecheck_gateway, public to firecheck_gateway_server;
grant select, insert, update, delete on all tables in schema firecheck_gateway to firecheck_gateway_server;
grant usage, select on all sequences in schema firecheck_gateway to firecheck_gateway_server;
grant select on public.assignments, public.enumerators, public.assignment_members to firecheck_gateway_server;
grant insert, update, delete on public.assignment_members to firecheck_gateway_server;
grant select, insert on public.drive_uploads to firecheck_gateway_server;
-- RLS applies even though this schema is not exposed to the Data API.
do $$ declare t text; begin
 foreach t in array array['settings','supervisors','sources','versions','uploads','upload_files','events'] loop
   execute format('alter table firecheck_gateway.%I enable row level security',t);
   execute format('create policy gateway_server on firecheck_gateway.%I to firecheck_gateway_server using (true) with check (true)',t);
 end loop;
end $$;
create policy gateway_server_read_assignments on public.assignments for select to firecheck_gateway_server using(true);
create policy gateway_server_read_enumerators on public.enumerators for select to firecheck_gateway_server using(true);
create policy gateway_server_members on public.assignment_members to firecheck_gateway_server using(true) with check(true);
create policy gateway_server_audit_read on public.drive_uploads for select to firecheck_gateway_server using(true);
create policy gateway_server_audit_insert on public.drive_uploads for insert to firecheck_gateway_server with check(true);
commit;
