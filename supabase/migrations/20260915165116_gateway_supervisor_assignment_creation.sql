-- Only the gateway database role may create supervisor-authorized assignments.
begin;
grant insert on public.assignments to firecheck_gateway_server;
create policy gateway_server_create_assignments on public.assignments
  for insert to firecheck_gateway_server with check(true);
commit;
