import { test, before, after } from "node:test";
import { strict as assert } from "node:assert";
import { readFile } from "node:fs/promises";
import { randomUUID, createHash } from "node:crypto";
import pg from "pg";
import { buildApp } from "../src/app.js";
import { Database } from "../src/db.js";
import { ApiError, validateMap } from "../src/domain.js";
import type { Drive, DriveFile } from "../src/drive.js";

const admin = "00000000-0000-0000-0000-000000000001";
const worker = "00000000-0000-0000-0000-000000000002";
const outsider = "00000000-0000-0000-0000-000000000003";
const assignment = "00000000-0000-0000-0000-000000000004";
const md5 = (b: Buffer) => createHash("md5").update(b).digest("hex");
class FakeDrive implements Drive {
  files = new Map<string, DriveFile>();
  bytes = new Map<string, Buffer>();
  sessions = new Map<string, { id: string; data: Buffer; size: number }>();
  failAfterWrite = false;
  constructor() {
    for (const id of ["input", "output", "published"])
      this.files.set(id, {
        id,
        name: id,
        mimeType: "application/vnd.google-apps.folder",
        driveId: "shared",
      });
  }
  async metadata(id: string) {
    const f = this.files.get(id);
    if (!f) throw new ApiError(502, "DRIVE_REQUEST_FAILED");
    return { ...f };
  }
  async children(id: string) {
    return [...this.files.values()].filter((f) => f.parents?.includes(id));
  }
  async folder(parent: string, name: string) {
    const id = randomUUID();
    this.files.set(id, {
      id,
      name,
      mimeType: "application/vnd.google-apps.folder",
      parents: [parent],
      driveId: "shared",
    });
    return id;
  }
  put(parent: string, name: string, bytes: Buffer) {
    const id = randomUUID();
    this.files.set(id, {
      id,
      name,
      mimeType: "application/octet-stream",
      parents: [parent],
      driveId: "shared",
      size: String(bytes.length),
      md5Checksum: md5(bytes),
    });
    this.bytes.set(id, bytes);
    return id;
  }
  async copy(id: string, parent: string) {
    const f = await this.metadata(id);
    return this.metadata(this.put(parent, f.name, this.bytes.get(id)!));
  }
  async empty(parent: string, name: string) {
    return this.put(parent, name, Buffer.alloc(0));
  }
  async stream(id: string, range?: string) {
    let bytes = this.bytes.get(id)!;
    const start = range ? Number(range.match(/\d+/)![0]) : 0;
    const headers: Record<string, string> = {};
    if (range) {
      headers["content-range"] =
        `bytes ${start}-${bytes.length - 1}/${bytes.length}`;
      bytes = bytes.subarray(start);
    }
    headers["content-length"] = String(bytes.length);
    return new Response(new Uint8Array(bytes), {
      status: range ? 206 : 200,
      headers,
    });
  }
  async begin(id: string, size: number) {
    const url = randomUUID();
    this.sessions.set(url, { id, data: Buffer.alloc(0), size });
    return url;
  }
  async status(url: string, size: number) {
    const s = this.sessions.get(url);
    return {
      offset: s?.data.length ?? 0,
      complete: s?.data.length === size,
      expired: !s,
    };
  }
  async chunk(url: string, bytes: Buffer, offset: number, size: number) {
    const s = this.sessions.get(url)!;
    assert.equal(offset, s.data.length);
    s.data = Buffer.concat([s.data, bytes]);
    if (s.data.length === size) {
      this.bytes.set(s.id, s.data);
      Object.assign(this.files.get(s.id)!, {
        size: String(size),
        md5Checksum: md5(s.data),
      });
    }
    if (this.failAfterWrite) {
      this.failAfterWrite = false;
      throw new Error("lost upstream response");
    }
  }
}
const adminUrl =
  process.env.TEST_DATABASE_URL ??
  "postgresql://postgres:local-gateway-test@127.0.0.1:55439/postgres";
const adminPool = new pg.Pool({ connectionString: adminUrl });
const databaseName = "gateway_test_" + randomUUID().replaceAll("-", "");
const testUrl = new URL(adminUrl);
testUrl.pathname = "/" + databaseName;
const pool = new pg.Pool({ connectionString: testUrl.toString() });
const routePool = new pg.Pool({
  connectionString: testUrl.toString(),
  options: "-c role=firecheck_gateway_server",
});
const drive = new FakeDrive();
const app = buildApp({
  database: new Database(routePool),
  drive,
  config: {
    inputRoot: "input",
    outputRoot: "output",
    publishedRoot: "published",
    sharedDrive: "shared",
  },
  authenticate: async (t) => {
    if (![admin, worker, outsider].includes(t))
      throw new ApiError(401, "SESSION_EXPIRED");
    return t;
  },
});
const call = (
  method: any,
  url: string,
  who = worker,
  body?: any,
  headers: Record<string, string> = {},
) =>
  app.inject({
    method,
    url,
    headers: { authorization: `Bearer ${who}`, ...headers },
    payload: body,
  });
let version: string;
let artifact: string;
const map = Buffer.from("published map fixture");
before(async () => {
  // Dedicated disposable database, never a live Supabase database.
  assert.match(pool.options.connectionString!, /@(127\.0\.0\.1|localhost):/);
  await adminPool.query(`create database ${databaseName}`);
  await pool.query(`do $$ begin
    if not exists(select 1 from pg_roles where rolname='anon') then create role anon;end if;
    if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated;end if;
    end $$;
    create schema auth; create function auth.uid() returns uuid language sql as $$ select null::uuid $$;
    create table public.enumerators(id uuid primary key);
    create table public.assignments(id uuid primary key,name text,closed_remotely boolean default false);
    create table public.assignment_members(assignment_id uuid references public.assignments(id),enumerator_id uuid references public.enumerators(id),role text,primary key(assignment_id,enumerator_id));
    create table public.drive_uploads(id uuid primary key,assignment_id uuid,uploaded_by uuid,drive_folder_path text,drive_folder_url text,file_count int);
    alter table public.assignments enable row level security;alter table public.assignment_members enable row level security;alter table public.enumerators enable row level security;alter table public.drive_uploads enable row level security;
    create function public.claim_assignment_by_name(text) returns uuid language sql as $$ select null::uuid $$;
    create function public.resolve_assignment_id_by_name(text) returns uuid language sql as $$ select null::uuid $$;
    grant execute on function public.claim_assignment_by_name(text),public.resolve_assignment_id_by_name(text) to authenticated;
  `);
  await pool.query(
    await readFile(
      new URL(
        "../../../supabase/migrations/20260915151740_drive_gateway.sql",
        import.meta.url,
      ),
      "utf8",
    ),
  );
  await pool.query("insert into public.enumerators values($1),($2),($3)", [
    admin,
    worker,
    outsider,
  ]);
  await pool.query("insert into public.assignments(id,name) values($1,$2)", [
    assignment,
    "Cebu",
  ]);
  await pool.query("insert into firecheck_gateway.supervisors values($1)", [
    admin,
  ]);
  assert.equal((await call("GET", "/v1/assignments")).statusCode, 503);
  await pool.query(
    await readFile(new URL("../sql/activate.sql", import.meta.url), "utf8"),
  );
  const folder = await drive.folder("input", "Cebu");
  for (const ext of ["shp", "shx", "dbf", "prj"])
    drive.put(folder, `buildings.${ext}`, map);
  assert.equal(
    (
      await call("PUT", `/v1/admin/assignments/${assignment}/source`, admin, {
        folderId: folder,
      })
    ).statusCode,
    200,
  );
  const published = await call(
    "POST",
    `/v1/admin/assignments/${assignment}/publish`,
    admin,
  );
  assert.equal(published.statusCode, 200, published.body);
  version = published.json().version;
  artifact = published.json().files[0].id;
  assert.equal(
    (
      await call(
        "PUT",
        `/v1/admin/assignments/${assignment}/members/${worker}`,
        admin,
      )
    ).statusCode,
    200,
  );
});
after(async () => {
  await app.close();
  await routePool.end();
  await pool.end();
  await adminPool.query(`drop database if exists ${databaseName}`);
  await adminPool.end();
});
test("missing or invalid sessions cannot list maps", async () => {
  assert.equal((await app.inject("/v1/assignments")).statusCode, 401);
  assert.equal((await call("GET", "/v1/assignments", "bad")).statusCode, 401);
});
test("worker listing and manifest expose no Drive IDs", async () => {
  const r = await call("GET", "/v1/assignments");
  assert.equal(r.json().assignments[0].id, assignment);
  const m = await call("GET", `/v1/assignments/${assignment}/manifest`);
  assert.equal(m.statusCode, 200);
  assert.equal(m.json().files[0].driveId, undefined);
});
test("outsider cannot guess assignment or artifact IDs", async () => {
  assert.deepEqual(
    (await call("GET", "/v1/assignments", outsider)).json().assignments,
    [],
  );
  assert.equal(
    (await call("GET", `/v1/assignments/${assignment}/manifest`, outsider))
      .statusCode,
    403,
  );
  assert.equal(
    (
      await call(
        "GET",
        `/v1/assignments/${assignment}/versions/${version}/files/${artifact}`,
        outsider,
      )
    ).statusCode,
    403,
  );
});
test("range download and edited publication protection", async () => {
  const url = `/v1/assignments/${assignment}/versions/${version}/files/${artifact}`;
  const r = await call("GET", url, worker, undefined, { range: "bytes=3-" });
  assert.equal(r.statusCode, 206);
  assert.equal(r.body, map.subarray(3).toString());
  const row = (
    await pool.query(
      "select manifest from firecheck_gateway.versions where id=$1",
      [version],
    )
  ).rows[0];
  const f = drive.files.get(row.manifest[0].driveId)!;
  const checksum = f.md5Checksum;
  f.md5Checksum = "bad";
  assert.equal((await call("GET", url)).statusCode, 409);
  f.md5Checksum = checksum;
});
test("worker cannot grant membership or register arbitrary Drive folders", async () => {
  assert.equal(
    (
      await call(
        "PUT",
        `/v1/admin/assignments/${assignment}/members/${outsider}`,
      )
    ).statusCode,
    403,
  );
  assert.equal(
    (
      await call("PUT", `/v1/admin/assignments/${assignment}/source`, admin, {
        folderId: "output",
      })
    ).statusCode,
    400,
  );
});
test("cutover revokes self-enrollment and private tables are inaccessible", async () => {
  const result = await pool.query(
    `select has_function_privilege('authenticated','public.claim_assignment_by_name(text)','execute') as can_claim,has_schema_privilege('authenticated','firecheck_gateway','usage') as can_read`,
  );
  assert.equal(result.rows[0].can_claim, false);
  assert.equal(result.rows[0].can_read, false);
  await pool.query("set role firecheck_gateway_server");
  try {
    assert.equal(
      (await pool.query("select id from public.assignments")).rowCount,
      1,
    );
  } finally {
    await pool.query("reset role");
  }
});
test("resumable upload survives lost response, rejects other owner, completes once", async () => {
  const id = randomUUID(),
    file = randomUUID();
  const bytes = Buffer.alloc(256 * 1024 + 12, 42);
  const manifest = {
    id,
    files: [
      { id: file, name: "buildings.dbf", size: bytes.length, md5: md5(bytes) },
    ],
  };
  const base = `/v1/uploads/${id}`;
  assert.equal(
    (
      await call(
        "POST",
        `/v1/assignments/${assignment}/uploads`,
        worker,
        manifest,
      )
    ).statusCode,
    200,
  );
  assert.equal(
    (
      await call(
        "POST",
        `/v1/assignments/${assignment}/uploads`,
        worker,
        manifest,
      )
    ).statusCode,
    200,
  );
  assert.equal((await call("GET", base, outsider)).statusCode, 404);
  assert.equal((await call("GET", `${base}/files/${file}`)).json().offset, 0);
  drive.failAfterWrite = true;
  assert.equal(
    (
      await call(
        "PUT",
        `${base}/files/${file}/chunks`,
        worker,
        bytes.subarray(0, 256 * 1024),
        { "content-type": "application/octet-stream", "upload-offset": "0" },
      )
    ).statusCode,
    503,
  );
  assert.equal(
    (await call("GET", `${base}/files/${file}`)).json().offset,
    256 * 1024,
  );
  const tail = await call(
    "PUT",
    `${base}/files/${file}/chunks`,
    worker,
    bytes.subarray(256 * 1024),
    {
      "content-type": "application/octet-stream",
      "upload-offset": String(256 * 1024),
    },
  );
  assert.equal(tail.statusCode, 200, tail.body);
  assert.equal(tail.json().complete, true);
  for (let i = 0; i < 2; i++)
    assert.equal(
      (await call("POST", `${base}/complete`)).json().complete,
      true,
    );
  assert.equal(
    (await pool.query("select * from public.drive_uploads where id=$1", [id]))
      .rowCount,
    1,
  );
  const conflict = {
    ...manifest,
    files: [{ ...manifest.files[0], md5: "0".repeat(32) }],
  };
  assert.equal(
    (
      await call(
        "POST",
        `/v1/assignments/${assignment}/uploads`,
        worker,
        conflict,
      )
    ).statusCode,
    409,
  );
});
test("incomplete upload never becomes complete", async () => {
  const id = randomUUID();
  await call("POST", `/v1/assignments/${assignment}/uploads`, worker, {
    id,
    files: [
      {
        id: randomUUID(),
        name: "roads.shp",
        size: 2,
        md5: md5(Buffer.from("hi")),
      },
    ],
  });
  assert.equal(
    (await call("POST", `/v1/uploads/${id}/complete`)).statusCode,
    409,
  );
});
test("closed assignment rejects new batches", async () => {
  await pool.query(
    "update public.assignments set closed_remotely=true where id=$1",
    [assignment],
  );
  try {
    const r = await call(
      "POST",
      `/v1/assignments/${assignment}/uploads`,
      worker,
      {
        id: randomUUID(),
        files: [
          {
            id: randomUUID(),
            name: "roads.shp",
            size: 2,
            md5: md5(Buffer.from("hi")),
          },
        ],
      },
    );
    assert.equal(r.statusCode, 409);
  } finally {
    await pool.query(
      "update public.assignments set closed_remotely=false where id=$1",
      [assignment],
    );
  }
});
test("map publication validation rejects partial component sets", () => {
  assert.throws(
    () =>
      validateMap([
        {
          id: randomUUID(),
          name: "roads.shp",
          size: 2,
          md5: "0".repeat(32),
          driveId: "x",
        },
      ]),
    ApiError,
  );
});
