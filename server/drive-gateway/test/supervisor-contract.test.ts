import { test, before, after } from "node:test";
import { strict as assert } from "node:assert";
import { randomUUID } from "node:crypto";
import pg from "pg";
import { initializeMigrationDatabase } from "./migration-fixture.js";
import { SharedTestDrive } from "./shared-drive-fixture.js";
import { buildApp } from "../src/app.js";
import { Database } from "../src/db.js";
import { ApiError } from "../src/domain.js";
const uri =
  process.env.TEST_DATABASE_URL ??
  "postgresql://postgres:local-sync-test@127.0.0.1:55441/postgres";
const url = new URL(uri);
assert.ok(["localhost", "127.0.0.1"].includes(url.hostname));
const databaseName = `supervisor_contract_${randomUUID().replaceAll("-", "")}`;
const adminPool = new pg.Pool({ connectionString: uri });
url.pathname = "/" + databaseName;
const pool = new pg.Pool({ connectionString: url.toString() });
const routePool = new pg.Pool({
  connectionString: url.toString(),
  options: "-c role=firecheck_gateway_server",
});
const supervisor = randomUUID(),
  worker = randomUUID(),
  outsider = randomUUID(),
  campaign = randomUUID();
const boundary = {
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
const app = buildApp({
  database: new Database(routePool),
  drive: new SharedTestDrive(),
  config: {
    inputRoot: "input",
    outputRoot: "output",
    publishedRoot: "published",
  },
  authenticate: async (token) => {
    if (![supervisor, worker, outsider].includes(token))
      throw new ApiError(401, "SESSION_EXPIRED");
    return token;
  },
});
const call = (
  method: "POST" | "PUT" | "DELETE",
  path: string,
  who: string,
  body?: any,
) =>
  app.inject({
    method,
    url: path,
    headers: { authorization: `Bearer ${who}` },
    payload: body,
  });
before(async () => {
  await adminPool.query(`create database ${databaseName}`);
  await initializeMigrationDatabase(pool);
  await pool.query(
    "insert into auth.users(id,email) values($1,'supervisor@dev.invalid'),($2,'worker@dev.invalid'),($3,'outsider@dev.invalid')",
    [supervisor, worker, outsider],
  );
  await pool.query("insert into firecheck_gateway.supervisors values($1)", [
    supervisor,
  ]);
});
after(async () => {
  await app.close();
  await routePool.end();
  await pool.end();
  await adminPool.query(`drop database ${databaseName}`);
  await adminPool.end();
});
test("campaign identity is an external UUID shared by supervisor-created assignments; creator alone is enrolled", async () => {
  assert.equal(
    (await pool.query("select to_regclass('public.campaigns') as campaigns"))
      .rows[0].campaigns,
    null,
  );
  for (const name of ["North", "South"]) {
    const id = randomUUID();
    const response = await call("POST", "/v1/admin/assignments", supervisor, {
      id,
      name,
      campaignId: campaign,
      boundary,
    });
    assert.equal(response.statusCode, 200, response.body);
    const assignment = (
      await pool.query(
        "select campaign_id,enumerator_id from public.assignments where id=$1",
        [id],
      )
    ).rows[0];
    assert.equal(assignment.campaign_id, campaign);
    assert.equal(assignment.enumerator_id, supervisor);
    const memberships = (
      await pool.query(
        "select enumerator_id,role from public.assignment_members where assignment_id=$1",
        [id],
      )
    ).rows;
    assert.deepEqual(memberships, [
      { enumerator_id: supervisor, role: "owner" },
    ]);
    assert.equal(
      (
        await call(
          "PUT",
          `/v1/admin/assignments/${id}/members/${worker}`,
          supervisor,
        )
      ).statusCode,
      200,
    );
    assert.equal(
      (
        await call(
          "PUT",
          `/v1/admin/assignments/${id}/members/${outsider}`,
          worker,
        )
      ).statusCode,
      403,
    );
    assert.equal(
      (
        await call(
          "DELETE",
          `/v1/admin/assignments/${id}/members/${supervisor}`,
          worker,
        )
      ).statusCode,
      403,
    );
    assert.equal(
      (
        await pool.query(
          "select 1 from public.assignment_members where assignment_id=$1 and enumerator_id=$2",
          [id, outsider],
        )
      ).rowCount,
      0,
    );
  }
});
test("assignment creation requires explicit campaign UUID and supervisor authorization", async () => {
  const id = randomUUID();
  for (const who of [worker, outsider]) {
    const denied = await call("POST", "/v1/admin/assignments", who, {
      id,
      name: "Denied",
      campaignId: campaign,
      boundary,
    });
    assert.equal(denied.statusCode, 403, denied.body);
    assert.equal(denied.json().code, "SUPERVISOR_REQUIRED");
  }
  const invalid = await call("POST", "/v1/admin/assignments", supervisor, {
    id,
    name: "Missing campaign",
    boundary,
  });
  assert.equal(invalid.statusCode, 400);
  assert.equal(
    (await pool.query("select 1 from public.assignments where id=$1", [id]))
      .rowCount,
    0,
  );
});
