import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { initializeMigrationDatabase } from "./migration-fixture.js";
import { randomUUID } from "node:crypto";
import pg from "pg";
import { Database } from "../src/db.js";
import { SharedTestDrive } from "./shared-drive-fixture.js";
import { geoJson, exportSharedMap } from "../src/shared-map-export.js";
const connection =
  process.env.SHARED_SYNC_TEST_DATABASE_URL ??
  "postgresql://postgres:local-sync-test@127.0.0.1:55441/postgres";
assert.match(connection, /@(127\.0\.0\.1|localhost):/);
const name = `shared_sync_${Date.now()}`;
const admin = new pg.Pool({ connectionString: connection });
const url = new URL(connection);
url.pathname = "/" + name;
const pool = new pg.Pool({ connectionString: url.toString() });
const serverPool=new pg.Pool({connectionString:url.toString(),options:'-c role=firecheck_gateway_server'});
const actor = randomUUID(),
  peer = randomUUID(),
  outsider = randomUUID(),
  map = randomUUID(),
  feature = randomUUID();
const polygon = {
  type: "Polygon",
  coordinates: [
    [
      [0, 0],
      [0, 1],
      [1, 1],
      [1, 0],
      [0, 0],
    ],
  ],
};
const building = {
  type: "Polygon",
  coordinates: [
    [
      [0.1, 0.1],
      [0.1, 0.2],
      [0.2, 0.2],
      [0.2, 0.1],
      [0.1, 0.1],
    ],
  ],
};
async function asUser(who: string, sql: string, values: any[] = []) {
  const c = await pool.connect();
  try {
    await c.query("begin");
    await c.query("select set_config('request.jwt.claim.sub',$1,true)", [who]);
    await c.query("set local role authenticated");
    const r = await c.query(sql, values);
    await c.query("commit");
    return r;
  } catch (e) {
    await c.query("rollback");
    throw e;
  } finally {
    c.release();
  }
}
function payload(who: string, remarks: string) {
  return {
    operation_id: randomUUID(),
    feature_type: "building",
    submission: {
      id: randomUUID(),
      feature_id: feature,
      submitted_by: who,
      does_not_exist: false,
      remarks,
      form_version: "legacy-v1",
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    },
  };
}
before(async () => {
  await admin.query(`create database ${name}`);
  await initializeMigrationDatabase(pool);
  await pool.query('grant firecheck_gateway_server to current_user with set true');
  await pool.query(
    `insert into auth.users(id,email) values($1,'actor@test.invalid'),($2,'peer@test.invalid'),($3,'outsider@test.invalid')`,
    [actor, peer, outsider],
  );
  await pool.query(
    `insert into public.assignments(id,enumerator_id,campaign_id,boundary_polygon,name)
 values($1,$2,$3,st_geomfromgeojson($4)::geography,'Pilot')`,
    [map, actor, randomUUID(), JSON.stringify(polygon)],
  );
  await pool.query(
    `insert into public.assignment_members values($1,$2,'owner',now()),($1,$3,'member',now()) on conflict do nothing`,
    [map, actor, peer],
  );
  await pool.query(
    `insert into public.features(id,assignment_id,feature_type,geometry) values($1,$2,'building',st_geomfromgeojson($3)::geography)`,
    [feature, map, JSON.stringify(building)],
  );
  await pool.query("select firecheck_sync.activate($1)", [map]);
});
after(async () => {
  await serverPool.end();
  await pool.end();
  if (process.env.KEEP_SHARED_TEST_DB==='1') console.log('Retained isolated database:',name);
  else await admin.query(`drop database if exists ${name}`);
  await admin.end();
});
let first: any;
test("member can bootstrap; outsider cannot read or infer map state", async () => {
  const r = await asUser(
    actor,
    "select public.get_shared_map_changes($1) data",
    [map],
  );
  assert.equal(r.rows[0].data.enabled, true);
  assert.equal(r.rows[0].data.bundles.at(-1).features[0].id, feature);
  await assert.rejects(
    asUser(outsider, "select public.get_shared_map_changes($1)", [map]),
    /not_member/,
  );
});
test("accepted operation receipt is exact and retry creates no revisions", async () => {
  first = payload(actor, "First");
  const query =
    "select public.submit_attribution_with_conflict_check($1) result";
  const a = await asUser(actor, query, [first]);
  assert.equal(a.rows[0].result.status, "committed");
  const before = (
    await pool.query(
      "select revision from firecheck_sync.maps where assignment_id=$1",
      [map],
    )
  ).rows[0].revision;
  const b = await asUser(actor, query, [first]);
  assert.deepEqual(a.rows, b.rows);
  assert.equal(
    (
      await pool.query(
        "select revision from firecheck_sync.maps where assignment_id=$1",
        [map],
      )
    ).rows[0].revision,
    before,
  );
  await assert.rejects(
    asUser(actor, query, [{ ...first, extra: "changed" }]),
    /operation_payload_mismatch/,
  );
});
test("conflict remains outside accepted projection; repeated retry preserves conflict", async () => {
  const p = payload(peer, "Competing");
  const q = "select public.submit_attribution_with_conflict_check($1) result";
  const a = await asUser(peer, q, [p]);
  assert.equal(a.rows[0].result.status, "conflict");
  assert.deepEqual((await asUser(peer, q, [p])).rows, a.rows);
  const row = (
    await pool.query(
      "select payload from firecheck_sync.current_features where feature_id=$1",
      [feature],
    )
  ).rows[0].payload;
  assert.equal(row.submissions.length, 1);
  assert.equal(row.submissions[0].id, first.submission.id);
});
test("concurrent retries commit once; conflict resolution receipt survives retry", async () => {
  const pending = payload(peer, "Resolve me");
  const q = "select public.submit_attribution_with_conflict_check($1) result";
  const responses = await Promise.all([
    asUser(peer, q, [pending]),
    asUser(peer, q, [pending]),
  ]);
  assert.deepEqual(responses[0]!.rows, responses[1]!.rows);
  const resolve =
    "select public.resolve_attribution($1,'keep_theirs',null) result";
  const a = await asUser(peer, resolve, [pending.submission.id]);
  const b = await asUser(peer, resolve, [pending.submission.id]);
  assert.deepEqual(a.rows, b.rows);
  assert.equal(
    (
      await pool.query("select count(*) from public.submissions where id=$1", [
        pending.submission.id,
      ])
    ).rows[0].count,
    "0",
  );
});
test("photo completion registers metadata once and produces a change", async () => {
  const id = randomUUID(),
    path = `${first.submission.id}/${id}.jpg`,
    time = new Date().toISOString();
  const q = "select public.register_uploaded_photo($1,$2,$3,$4)";
  await asUser(actor, q, [id, first.submission.id, path, time]);
  const rev = (
    await pool.query(
      "select revision from firecheck_sync.maps where assignment_id=$1",
      [map],
    )
  ).rows[0].revision;
  await asUser(actor, q, [id, first.submission.id, path, time]);
  assert.equal(
    (
      await pool.query(
        "select revision from firecheck_sync.maps where assignment_id=$1",
        [map],
      )
    ).rows[0].revision,
    rev,
  );
  await assert.rejects(
    asUser(peer, q, [id, first.submission.id, path, time]),
    /not_member/,
  );
});
test("explicit additional observation preserves both surveys", async () => {
  const additional = {
    ...payload(actor, "Another household"),
    additional_observation: true,
  };
  const r = await asUser(
    actor,
    "select public.submit_attribution_with_conflict_check($1) result",
    [additional],
  );
  assert.equal(r.rows[0].result.status, "committed");
  const row = (
    await pool.query(
      "select payload from firecheck_sync.current_features where feature_id=$1",
      [feature],
    )
  ).rows[0].payload;
  assert.equal(row.submissions.length, 2);
});
test("same transaction emits one complete revision; tombstone is durable", async () => {
  const c = await pool.connect();
  try {
    await c.query("begin");
    await c.query("update public.features set geometry=geometry where id=$1", [
      feature,
    ]);
    await c.query(
      "update public.submissions set remarks='Updated' where id=$1",
      [first.submission.id],
    );
    await c.query("commit");
  } finally {
    c.release();
  }
  const bundle = (
    await pool.query(
      "select * from firecheck_sync.changes where assignment_id=$1 order by revision desc limit 1",
      [map],
    )
  ).rows[0];
  assert.equal(
    bundle.payload.submissions.find((s: any) => s.id === first.submission.id)
      .attribute_values.remarks,
    "Updated",
  );
  const before = bundle.revision;
  await pool.query("delete from public.features where id=$1", [feature]);
  const latest = (
    await pool.query(
      "select * from firecheck_sync.changes where assignment_id=$1 order by revision desc limit 1",
      [map],
    )
  ).rows[0];
  assert.equal(BigInt(latest.revision), BigInt(before) + 1n);
  assert.equal(latest.payload.deleted, true);
});
test("GIS export includes unsurveyed geometry and excludes pending/deleted and private fields", () => {
  const features = [
    { id: "one", geometry_geojson: building, submissions: [] },
    {
      id: "two",
      geometry_geojson: building,
      submissions: [
        {
          id: "s",
          attribute_values: {
            remarks: "private",
            household: { name: "private" },
            building: { storeys: 2, cbms_id: "private" },
          },
        },
      ],
    },
    { id: "three", deleted: true },
    { id: "four", pending_dedup: true },
  ];
  const gis = geoJson({
    schema_version: 1,
    assignment_id: map,
    revision: 4,
    assignment: {},
    features,
  });
  assert.equal(gis.features.length, 2);
  assert.ok(!JSON.stringify(gis).includes("private"));
});

test("combined export publishes verified native download and one Current; failure preserves prior pointer", async () => {
  const drive = new SharedTestDrive();
  await pool.query(
    `insert into firecheck_gateway.sources(assignment_id,folder_id,registered_by) values($1,'source',$2)`,
    [map, actor],
  );
  const db = new Database(serverPool);
  assert.equal(await exportSharedMap(db, drive, "output"), true);
  const first = (
    await pool.query(
      "select current_version from firecheck_gateway.sources where assignment_id=$1",
      [map],
    )
  ).rows[0].current_version;
  const version = (
    await pool.query(
      "select manifest from firecheck_gateway.versions where id=$1",
      [first],
    )
  ).rows[0];
  assert.equal(version.manifest[0].name, "shared-map.json");
  const native = JSON.parse(
    drive.bytes.get(version.manifest[0].driveId)!.toString(),
  );
  assert.equal(native.assignment_id, map);
  const id = randomUUID();
  await pool.query(
    `insert into public.features(id,assignment_id,feature_type,geometry) values($1,$2,'building',st_geomfromgeojson($3)::geography)`,
    [id, map, JSON.stringify(building)],
  );
  drive.fail = true;
  await assert.rejects(
    exportSharedMap(db, drive, "output"),
    /Drive unavailable/,
  );
  assert.equal(
    (
      await pool.query(
        "select current_version from firecheck_gateway.sources where assignment_id=$1",
        [map],
      )
    ).rows[0].current_version,
    first,
  );
  drive.fail = false;
  await pool.query(
    "update firecheck_sync.export_jobs set next_attempt_at=now()",
  );
  assert.equal(await exportSharedMap(db, drive, "output"), true);
  assert.equal(
    [...drive.files.values()].filter((f) => f.name === "Current.geojson")
      .length,
    1,
  );
  const current = [...drive.files.values()].find(
    (f) => f.name === "Current.geojson",
  )!;
  assert.equal(
    JSON.parse(drive.bytes.get(current.id)!.toString()).features.length,
    1,
  );
  assert.equal(await exportSharedMap(db, drive, "output"), false);
});

test("private replication tables enforce RLS and deny direct client writes", async () => {
  const { rows } =
    await pool.query(`select relname,relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='firecheck_sync' and c.relkind='r'`);
  assert.ok(rows.length >= 8);
  assert.ok(rows.every((r) => r.relrowsecurity));
  const privileges = (
    await pool.query(`select has_table_privilege('authenticated','public.features','UPDATE') feature_write,
  has_function_privilege('anon','public.get_shared_map_changes(uuid,bigint,bigint)','EXECUTE') anonymous_read,
  has_function_privilege('authenticated','public.upload_submission_bundle(jsonb)','EXECUTE') bypass`)
  ).rows[0];
  assert.deepEqual(privileges, {
    feature_write: false,
    anonymous_read: false,
    bypass: false,
  });
});

test('new-feature retries and geometry edits share the durable feed',async()=>{
 const id=randomUUID();const shape={type:'Polygon',coordinates:[[[0.5,0.5],[0.5,0.6],[0.6,0.6],[0.6,0.5],[0.5,0.5]]]};
 const p={id,assignment_id:map,feature_type:'building',geometry_geojson:JSON.stringify(shape),is_new:true};
 const results=await Promise.all([asUser(actor,'select public.submit_new_feature_with_dedup_check($1) result',[p]),
  asUser(actor,'select public.submit_new_feature_with_dedup_check($1) result',[p])]);
 assert.deepEqual(results[0]!.rows,results[1]!.rows);
 assert.equal((await pool.query('select count(*) from public.features where id=$1',[id])).rows[0].count,'1');
 const revised={type:'Polygon',coordinates:[[[0.5,0.5],[0.5,0.61],[0.61,0.61],[0.61,0.5],[0.5,0.5]]]};
 const rev=randomUUID();
 await asUser(actor,'select public.update_feature_geometry($1,$2,$3,$4,now(),null)',[rev,id,JSON.stringify(shape),JSON.stringify(revised)]);
 const row=(await pool.query('select payload from firecheck_sync.current_features where feature_id=$1',[id])).rows[0];
 assert.deepEqual(row.payload.geometry_geojson,revised);
 const submission={...payload(actor,'Completed geometry'),submission:{...payload(actor,'Completed geometry').submission,feature_id:id}};
 await asUser(actor,'select public.submit_attribution_with_conflict_check($1)',[submission]);
 await asUser(actor,'select public.update_feature_geometry($1,$2,$3,$4,now(),null)',[rev,id,JSON.stringify(shape),JSON.stringify(revised)]);
 await assert.rejects(asUser(actor,'select public.update_feature_geometry($1,$2,$3,$4,now(),null)',[rev,id,JSON.stringify(shape),JSON.stringify(shape)]),/geometry_operation_id_reused/);
});

test('assignment metadata changes advance the version without a broken empty bundle',async()=>{
 const before=Number((await pool.query('select revision from firecheck_sync.maps where assignment_id=$1',[map])).rows[0].revision);
 await pool.query("update public.assignments set name='Renamed pilot' where id=$1",[map]);
 const page=(await asUser(actor,'select public.get_shared_map_changes($1,$2,null) data',[map,before])).rows[0].data;
 assert.equal(page.next_revision,before+1);assert.deepEqual(page.bundles[0].features,[]);
});

test('split recovers a preuploaded child, preserves its survey and rejects mismatches',async()=>{
 const parent=randomUUID(),child=randomUUID(),revision=randomUUID();
 const box=(x0:number,x1:number)=>({type:'Polygon',coordinates:[[[x0,0.7],[x0,0.8],[x1,0.8],[x1,0.7],[x0,0.7]]]});
 const original=box(0.7,0.8),first=box(0.7,0.75),second=box(0.75,0.8);
 await pool.query(`insert into public.features(id,assignment_id,feature_type,geometry,is_new)
 values($1,$3,'building',st_geomfromgeojson($4)::geography,false),($2,$3,'building',st_geomfromgeojson($5)::geography,true)`,[parent,child,map,JSON.stringify(original),JSON.stringify(second)]);
 const survey=payload(actor,'Retain child survey');survey.submission.feature_id=child;
 await asUser(actor,'select public.submit_attribution_with_conflict_check($1)',[survey]);
 const sql='select public.apply_feature_geometry_operation($1,$2,$3,$4,now(),null,\'split\',$5,$6)';
 const args=[revision,parent,JSON.stringify(original),JSON.stringify(first),child,JSON.stringify(second)];
 await assert.rejects(asUser(outsider,sql,args),/forbidden/);
 await assert.rejects(asUser(actor,sql,[...args.slice(0,5),JSON.stringify(box(0.76,0.8))]),/split_feature_conflict/);
 // Exact child geometry alone is insufficient: halves must cover the parent.
 await assert.rejects(asUser(actor,sql,[revision,parent,JSON.stringify(original),JSON.stringify(box(0.7,0.74)),child,JSON.stringify(second)]),/split_feature_conflict/);
 await asUser(actor,sql,args);
 const after=(await pool.query('select revision from firecheck_sync.maps where assignment_id=$1',[map])).rows[0].revision;
 await asUser(actor,sql,args);
 assert.equal((await pool.query('select revision from firecheck_sync.maps where assignment_id=$1',[map])).rows[0].revision,after);
 const retained=(await pool.query('select f.split_from_id,s.remarks from public.features f join public.submissions s on s.feature_id=f.id where f.id=$1',[child])).rows[0];
 assert.equal(retained.split_from_id,parent);assert.equal(retained.remarks,'Retain child survey');
 assert.equal((await pool.query('select count(*) from public.feature_geometry_revisions where id=$1',[revision])).rows[0].count,'1');
 const bundle=(await pool.query('select feature_id from firecheck_sync.changes where assignment_id=$1 and revision=$2',[map,after])).rows.map(r=>r.feature_id);
 assert.deepEqual(bundle.sort(),[parent,child].sort());
});
