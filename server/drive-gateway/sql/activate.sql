-- Run only after verifying server Drive access, supervisor identities, the
-- membership roster and the new mobile build. This affects old clients.
begin;
revoke execute on function public.claim_assignment_by_name(text) from public, anon, authenticated;
revoke execute on function public.resolve_assignment_id_by_name(text) from public, anon, authenticated;
drop policy if exists drive_uploads_member_insert on public.drive_uploads;
update firecheck_gateway.settings set enabled=true where id=true;
commit;
