import { readFile, readdir } from "node:fs/promises";
import type pg from "pg";

/** Minimal local Supabase surfaces; this does not emulate the Storage HTTP API. */
export async function initializeMigrationDatabase(
  pool: pg.Pool,
  through?: string,
  options: { legacyPublicGrants?: boolean } = {},
) {
  await pool.query(`create schema auth;create schema storage;create publication supabase_realtime;
 create function auth.uid() returns uuid language sql as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb default '{}');
 create table storage.buckets(id text primary key,name text,public boolean);
 create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text,created_at timestamptz default now());
 alter table storage.objects enable row level security;
 grant usage on schema public,auth to authenticated;
 grant execute on function auth.uid() to authenticated;
 `);
  // Existing Supabase projects retain historical public-table privileges. Seed
  // defaults before any tables exist so migrations must actually revoke DML.
  if (options.legacyPublicGrants) {
    await pool.query(`alter default privileges in schema public
      grant all on tables to anon, authenticated, service_role`);
  }
  const dir = new URL("../../../supabase/migrations/", import.meta.url);
  for (const file of (await readdir(dir))
    .filter((f) => f.endsWith(".sql") && (!through || f <= through))
    .sort()) {
    const sql = await readFile(new URL(file, dir), "utf8");
    // Historical geometry RPCs have broken unqualified PostGIS declarations;
    // the new migration fixes them. Validate every newly introduced function.
    await pool.query(
      `set check_function_bodies=${file.startsWith("202608231") ? "off" : "on"};\n` +
        sql,
    );
  }
}
