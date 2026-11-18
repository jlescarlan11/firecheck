-- Provision these Vault secrets through the dashboard before running:
-- firecheck_export_worker_url: full HTTPS URL ending in /v1/internal/shared-map-exports/run
-- firecheck_export_worker_token: matches the gateway EXPORT_WORKER_TOKEN secret
-- Run with an administrative database connection. No credentials in this file.
create extension if not exists pg_cron;
create extension if not exists pg_net;
do $$ begin
 if (select count(*) from vault.decrypted_secrets where name in
   ('firecheck_export_worker_url','firecheck_export_worker_token'))<>2 then
  raise exception 'Configure both FireCheck worker Vault secrets first';
 end if;
end $$;
select cron.schedule('firecheck-shared-map-exports','* * * * *',$job$
 select net.http_post(
  url:=(select decrypted_secret from vault.decrypted_secrets where name='firecheck_export_worker_url'),
  headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer ' ||
    (select decrypted_secret from vault.decrypted_secrets where name='firecheck_export_worker_token')),
  body:='{}'::jsonb,timeout_milliseconds:=120000
 );
$job$);
