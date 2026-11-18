import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import pg from "pg";
import { initializeMigrationDatabase } from "./migration-fixture.js";

const migration = "20261118050717_authorize_photo_storage_mutations.sql";
const connection =
  process.env.SHARED_SYNC_TEST_DATABASE_URL ??
  "postgresql://postgres:local-sync-test@127.0.0.1:55441/postgres";
assert.match(connection, /@(127\.0\.0\.1|localhost):/);

for (const mode of ["fresh", "upgrade"] as const) {
  test(`${mode}: real Storage object roles preserve accepted evidence and isolate mutations`, async (t) => {
    const name = `photo_storage_${randomUUID().replaceAll("-", "")}`;
    const admin = new pg.Pool({ connectionString: connection });
    const url = new URL(connection);
    url.pathname = "/" + name;
    const db = new pg.Pool({ connectionString: url.toString() });
    const actor = randomUUID(),
      peer = randomUUID(),
      outsider = randomUUID();
    const map = randomUUID(),
      otherMap = randomUUID(),
      feature = randomUUID(),
      otherFeature = randomUUID();
    const otherSid = randomUUID();
    const sid = randomUUID(),
      secondSid = randomUUID(),
      peerSid = randomUUID();
    const photo = randomUUID(),
      path = `${sid}/${photo}.jpg`;
    async function as(
      role: string,
      who: string | null,
      sql: string,
      values: unknown[] = [],
    ) {
      const c = await db.connect();
      try {
        await c.query("begin");
        await c.query("select set_config('request.jwt.claim.sub',$1,true)", [
          who ?? "",
        ]);
        await c.query(`set local role ${role}`);
        const result = await c.query(sql, values);
        await c.query("commit");
        return result;
      } catch (e) {
        await c.query("rollback");
        throw e;
      } finally {
        c.release();
      }
    }
    const user = (who: string, sql: string, values: unknown[] = []) =>
      as("authenticated", who, sql, values);
    const insert =
      "insert into storage.objects(bucket_id,name,owner_id,metadata) values('photos',$1,$2,'{}')";
    async function deniedMutation(
      who: string | null,
      action: "insert" | "update" | "rename" | "delete",
      target = path,
    ) {
      const role = who === null ? "anon" : "authenticated";
      if (action === "insert") {
        await assert.rejects(
          as(role, who, insert, [target, who]),
          /row-level security/,
        );
      } else {
        const q =
          action === "update"
            ? "update storage.objects set metadata='{\"attack\":true}' where name=$1"
            : action === "rename"
              ? "update storage.objects set name=name || '.moved' where name=$1"
              : "delete from storage.objects where name=$1";
        assert.equal((await as(role, who, q, [target])).rowCount, 0);
      }
    }
    try {
      await admin.query(`create database ${name}`);
      await initializeMigrationDatabase(
        db,
        mode === "upgrade"
          ? "20260916123208_recover_preuploaded_split_features.sql"
          : undefined,
        { legacyPublicGrants: true },
      );
      // These are the relevant platform-owned Storage grants/columns, absent
      // from the shared-map harness. Real HTTP/storage service parity is separate.
      await db.query(`alter table storage.objects add column owner_id text, add column metadata jsonb;
        create unique index storage_objects_bucket_name on storage.objects(bucket_id,name);
        grant usage on schema storage,auth to anon,authenticated,service_role;
        grant execute on function auth.uid() to anon,authenticated,service_role;
        grant select,insert,update,delete on storage.objects to anon,authenticated,service_role;
        create policy service_storage on storage.objects to service_role using(true) with check(true)`);
      if (mode === "upgrade") {
        await db.query(
          "insert into storage.objects(bucket_id,name) values('photos','legacy/ambiguous.jpg')",
        );
        // Characterize the original exploit before applying the forward migration.
        await user(outsider, insert, [path, outsider]);
        await db.query("delete from storage.objects where name=$1", [path]);
        await db.query(
          await readFile(
            new URL(
              `../../../supabase/migrations/${migration}`,
              import.meta.url,
            ),
            "utf8",
          ),
        );
      }
      await db.query(
        "insert into auth.users(id,email) values($1,'author@test.invalid'),($2,'peer@test.invalid'),($3,'outsider@test.invalid')",
        [actor, peer, outsider],
      );
      await db.query(
        `insert into public.assignments(id,enumerator_id,campaign_id,boundary_polygon,name)
        select id,$1,$2,st_geomfromtext('POLYGON((0 0,0 1,1 1,1 0,0 0))',4326)::geography,'Photo test'
        from unnest($3::uuid[]) id`,
        [actor, randomUUID(), [map, otherMap]],
      );
      await db.query(
        "insert into public.assignment_members values($1,$2,'owner',now()),($1,$3,'member',now()),($4,$2,'member',now()) on conflict do nothing",
        [map, actor, peer, otherMap],
      );
      await db.query(
        "insert into public.features(id,assignment_id,feature_type,geometry) values($1,$2,'building',st_geomfromtext('POLYGON((0 0,0 .1,.1 .1,.1 0,0 0))',4326)::geography)",
        [feature, map],
      );
      await db.query(
        "insert into public.submissions(id,feature_id,submitted_by) values($1,$4,$5),($2,$4,$5),($3,$4,$6)",
        [sid, secondSid, peerSid, feature, actor, peer],
      );
      await db.query(
        "insert into public.features(id,assignment_id,feature_type,geometry) select $1,$2,feature_type,geometry from public.features where id=$3",
        [otherFeature, otherMap, feature],
      );
      await db.query(
        "insert into public.submissions(id,feature_id,submitted_by) values($1,$2,$3)",
        [otherSid, otherFeature, actor],
      );
      await t.test(
        "author upload precedes registration; owner claims confer no authority; same path upsert retries",
        async () => {
          assert.equal(
            (
              await db.query("select count(*) from public.photos where id=$1", [
                photo,
              ])
            ).rows[0].count,
            "0",
          );
          await user(actor, insert, [path, outsider]);
          await user(
            actor,
            "insert into storage.objects(bucket_id,name,owner_id) values('photos',$1,$2) on conflict(bucket_id,name) do update set metadata='{}'",
            [path, actor],
          );
          const register =
            "select public.register_uploaded_photo($1,$2,$3,now())";
          await user(actor, register, [photo, sid, path]);
          await user(actor, register, [photo, sid, path]);
          assert.equal(
            (
              await db.query("select count(*) from public.photos where id=$1", [
                photo,
              ])
            ).rows[0].count,
            "1",
          );
          await assert.rejects(
            user(peer, register, [photo, sid, path]),
            /not_member/,
          );
        },
      );
      await t.test(
        "anonymous, peers (including assignment owner), nonmembers cannot mutate another author",
        async () => {
          const peerPath = `${peerSid}/${randomUUID()}.jpg`;
          await user(peer, insert, [peerPath, actor]);
          for (const who of [null, peer, outsider]) {
            for (const action of [
              "insert",
              "update",
              "rename",
              "delete",
            ] as const) {
              await deniedMutation(
                who,
                action,
                action === "insert" ? `${sid}/${randomUUID()}.jpg` : path,
              );
            }
          }
          await assert.rejects(
            user(peer, insert, [`${otherSid}/${randomUUID()}.jpg`, peer]),
            /row-level security/,
          );
          await deniedMutation(actor, "update", peerPath);
          await deniedMutation(actor, "delete", peerPath);
          const privileges = (
            await db.query(
              "select has_table_privilege('authenticated','public.submissions','UPDATE') submission_update, has_table_privilege('authenticated','public.features','UPDATE') feature_update, has_table_privilege('authenticated','public.photos','UPDATE') retained_photo_update",
            )
          ).rows[0];
          assert.deepEqual(privileges, {
            submission_update: false,
            feature_update: false,
            retained_photo_update: true,
          });
          await assert.rejects(
            user(
              actor,
              "update public.features set assignment_id=$1 where id=$2",
              [otherMap, feature],
            ),
            /permission denied/,
          );
          await assert.rejects(
            user(
              actor,
              "update public.submissions set submitted_by=$1 where id=$2",
              [actor, peerSid],
            ),
            /permission denied/,
          );
          await assert.rejects(
            user(
              actor,
              "insert into public.submissions(id,feature_id,submitted_by) values($1,$2,$3)",
              [randomUUID(), feature, actor],
            ),
            /permission denied/,
          );
        },
      );
      await t.test(
        "malformed paths, unknown parents and reused registered photo UUIDs fail closed",
        async () => {
          for (const bad of [
            "legacy/ambiguous.jpg",
            `${sid}/${randomUUID()}.png`,
            `${sid}/../${photo}.jpg`,
            `${sid}/${photo}.jpg/extra`,
            `${sid.toUpperCase()}/${photo}.jpg`,
            `${randomUUID()}/${randomUUID()}.jpg`,
            `${secondSid}/${photo}.jpg`,
            `${sid}/not-a-uuid.jpg`,
            `${sid}/{${photo}}.jpg`,
            `${sid}%2F${photo}.jpg`,
            `${sid}/${photo}.jpg\n`,
            "",
          ]) {
            await assert.rejects(
              user(actor, insert, [bad, actor]),
              /row-level security/,
            );
          }
          if (mode === "upgrade")
            assert.equal(
              (
                await db.query(
                  "select count(*) from storage.objects where name='legacy/ambiguous.jpg'",
                )
              ).rows[0].count,
              "1",
            );
        },
      );
      await t.test(
        "read-only legacy inventory distinguishes review items from canonical evidence",
        async () => {
          const missingPath = `${randomUUID()}/${randomUUID()}.jpg`;
          await db.query(
            "insert into storage.objects(bucket_id,name) values('photos',$1)",
            [missingPath],
          );
          const inventory = await db.query(
            await readFile(
              new URL(
                "../../../supabase/diagnostics/photo_storage_review.sql",
                import.meta.url,
              ),
              "utf8",
            ),
          );
          assert.ok(
            inventory.rows
              .find((row) => row.name === missingPath)
              .reasons.includes("missing_submission"),
          );
          assert.equal(
            inventory.rows.some((row) => row.name === path),
            false,
          );
          if (mode === "upgrade")
            assert.ok(
              inventory.rows
                .find((row) => row.name === "legacy/ambiguous.jpg")
                .reasons.includes("noncanonical_path"),
            );
          assert.equal(
            (
              await db.query(
                "select count(*) from storage.objects where name=$1",
                [missingPath],
              )
            ).rows[0].count,
            "1",
          );
        },
      );
      await t.test(
        "renames and bucket moves cannot relabel evidence even between owned submissions",
        async () => {
          for (const destination of [
            `${sid}/${randomUUID()}.jpg`,
            `${secondSid}/${randomUUID()}.jpg`,
            `${peerSid}/${randomUUID()}.jpg`,
            `${otherSid}/${randomUUID()}.jpg`,
          ]) {
            await assert.rejects(
              user(actor, "update storage.objects set name=$2 where name=$1", [
                path,
                destination,
              ]),
              /photo_object_identity_immutable|row-level security/,
            );
          }
          await assert.rejects(
            user(
              actor,
              "update storage.objects set bucket_id='other' where name=$1",
              [path],
            ),
            /photo_object_identity_immutable|row-level security/,
          );
          // A permissive policy for an unrelated bucket must not allow moves into photos.
          await db.query(
            "create policy other_bucket on storage.objects to authenticated using(bucket_id='other') with check(bucket_id='other')",
          );
          const incoming = `${sid}/${randomUUID()}.jpg`;
          await db.query(
            "insert into storage.objects(bucket_id,name) values('other',$1)",
            [incoming],
          );
          await assert.rejects(
            user(
              actor,
              "update storage.objects set bucket_id='photos' where bucket_id='other' and name=$1",
              [incoming],
            ),
            /photo_object_identity_immutable/,
          );
        },
      );
      await t.test(
        "policy helpers have restricted execution and fixed search paths",
        async () => {
          const acl = (
            await db.query(
              "select has_function_privilege('anon','firecheck_storage.can_mutate_photo_object(text,boolean)','execute') anon,has_function_privilege('authenticated','firecheck_storage.can_mutate_photo_object(text,boolean)','execute') authenticated,has_function_privilege('authenticated','firecheck_storage.keep_photo_object_identity()','execute') trigger_call",
            )
          ).rows[0];
          assert.equal(
            (
              await db.query(
                "select has_schema_privilege('anon','firecheck_storage','usage') access",
              )
            ).rows[0].access,
            false,
          );
          assert.equal(
            (
              await db.query(
                "select to_regprocedure('public.can_mutate_photo_object(text,boolean)') fn",
              )
            ).rows[0].fn,
            null,
          );
          assert.deepEqual(acl, {
            anon: false,
            authenticated: true,
            trigger_call: false,
          });
          assert.equal(
            (
              await db.query(
                "select bool_and(proconfig @> array['search_path=\"\"']) secure from pg_proc where oid in ('firecheck_storage.can_mutate_photo_object(text,boolean)'::regprocedure,'firecheck_storage.keep_photo_object_identity()'::regprocedure)",
              )
            ).rows[0].secure,
            true,
          );
        },
      );
      await t.test(
        "revocation immediately blocks writes; public GIS URLs remain intentionally public",
        async () => {
          await db.query(
            "delete from public.assignment_members where assignment_id=$1 and enumerator_id=$2",
            [map, actor],
          );
          for (const action of [
            "insert",
            "update",
            "rename",
            "delete",
          ] as const)
            await deniedMutation(
              actor,
              action,
              action === "insert" ? `${sid}/${randomUUID()}.jpg` : path,
            );
          await assert.rejects(
            user(
              actor,
              "select public.register_uploaded_photo($1,$2,$3,now())",
              [photo, sid, path],
            ),
            /not_member/,
          );
          assert.equal(
            (
              await db.query(
                "select public from storage.buckets where id='photos'",
              )
            ).rows[0].public,
            true,
          );
          assert.equal(
            (
              await user(
                actor,
                "select name from storage.objects where name=$1",
                [path],
              )
            ).rowCount,
            1,
          );
          await db.query(
            "insert into public.assignment_members values($1,$2,'owner',now())",
            [map, actor],
          );
        },
      );
      await t.test(
        "members cannot reopen, replace or truncate canonical assignment closure",
        async () => {
          await db.query(
            "update public.assignments set closed_remotely=true where id=$1",
            [map],
          );
          await assert.rejects(async () => {
            await user(
              actor,
              "update public.assignments set closed_remotely=false where id=$1",
              [map],
            );
            assert.equal(
              (
                await user(actor, "delete from storage.objects where name=$1", [
                  path,
                ])
              ).rowCount,
              1,
            );
          }, /permission denied/);
          await assert.rejects(
            user(actor, "delete from public.assignments where id=$1", [map]),
            /permission denied/,
          );
          await assert.rejects(
            user(actor, "update public.assignments set id=$2 where id=$1", [
              map,
              randomUUID(),
            ]),
            /permission denied/,
          );
          await assert.rejects(
            user(
              actor,
              "insert into public.assignments(id,enumerator_id,campaign_id,boundary_polygon) select $1,enumerator_id,campaign_id,boundary_polygon from public.assignments where id=$2",
              [randomUUID(), map],
            ),
            /permission denied/,
          );
          await assert.rejects(
            user(actor, "truncate public.assignments cascade"),
            /permission denied/,
          );
          assert.equal(
            (
              await db.query(
                "select closed_remotely from public.assignments where id=$1",
                [map],
              )
            ).rows[0].closed_remotely,
            true,
          );
          assert.equal(
            (
              await db.query(
                "select count(*) from storage.objects where name=$1",
                [path],
              )
            ).rows[0].count,
            "1",
          );
          await db.query(
            "update public.assignments set closed_remotely=false where id=$1",
            [map],
          );
          assert.equal(
            (
              await user(
                actor,
                "select id from public.assignments where id=$1",
                [map],
              )
            ).rowCount,
            1,
          );
          // Explicit gateway supervisor provisioning authority remains intact.
          assert.equal(
            (
              await as(
                "firecheck_gateway_server",
                actor,
                "insert into public.assignments(id,enumerator_id,campaign_id,boundary_polygon) select $1,enumerator_id,campaign_id,boundary_polygon from public.assignments where id=$2",
                [randomUUID(), map],
              )
            ).rowCount,
            1,
          );
        },
      );
      await t.test(
        "closed assignments retain in-flight upload/registration and retry; service cleanup is supported",
        async () => {
          const cleanup = `${sid}/${randomUUID()}.jpg`;
          await user(actor, insert, [cleanup, actor]);
          assert.equal(
            (
              await user(actor, "delete from storage.objects where name=$1", [
                cleanup,
              ])
            ).rowCount,
            1,
          );
          await db.query(
            "update public.assignments set closed_remotely=true where id=$1",
            [map],
          );
          const pending = randomUUID(),
            pendingPath = `${sid}/${pending}.jpg`;
          await user(actor, insert, [pendingPath, actor]);
          await user(
            actor,
            "select public.register_uploaded_photo($1,$2,$3,now())",
            [pending, sid, pendingPath],
          );
          assert.equal(
            (
              await user(
                actor,
                "update storage.objects set metadata='{}' where name=$1",
                [pendingPath],
              )
            ).rowCount,
            1,
          );
          await deniedMutation(actor, "delete", path);
          assert.equal(
            (
              await as(
                "service_role",
                null,
                "delete from storage.objects where bucket_id='photos'",
              )
            ).rowCount! >= 2,
            true,
          );
        },
      );
    } finally {
      await db.end();
      await admin.query(`drop database if exists ${name}`);
      await admin.end();
    }
  });
}
