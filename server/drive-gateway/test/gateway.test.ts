import { test, before, after } from "node:test";
import { strict as assert } from "node:assert";
import { readFile } from "node:fs/promises";
import { randomUUID, createHash } from "node:crypto";
import pg from "pg";
import { buildApp } from "../src/app.js";
import { Database } from "../src/db.js";
import { publicationReferences } from "../src/orphan-inventory.js";
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
  async folder(parent: string, name: string, key?: string) {
    const id = randomUUID();
    this.files.set(id, {
      id,
      name,
      ...(key ? { appProperties: { firecheckOutputKey: key } } : {}),
      mimeType: "application/vnd.google-apps.folder",
      parents: [parent],
      driveId: "shared",
    });
    return id;
  }
  async managedFolder(parent: string, name: string, key: string) {
    const existing = (await this.children(parent)).find(
      (f) => f.appProperties?.firecheckOutputKey === key,
    );
    if (existing) return existing;
    const id = await this.folder(parent, name);
    this.files.get(id)!.appProperties = { firecheckOutputKey: key };
    return this.metadata(id);
  }
  async relocate(id: string, parent: string, name: string) {
    Object.assign(this.files.get(id)!, { name, parents: [parent] });
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
    create table public.enumerators(id uuid primary key,display_name text default 'Surveyor');
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
test("one map output keeps collaborators separate and archives superseded batches", async () => {
  await pool.query(
    "update public.enumerators set display_name='Alex' where id=$1",
    [admin],
  );
  await pool.query(
    "update public.enumerators set display_name='Sam' where id=$1",
    [worker],
  );
  await call(
    "PUT",
    `/v1/admin/assignments/${assignment}/members/${admin}`,
    admin,
  );
  async function create(who: string) {
    const id = randomUUID(),
      file = randomUUID(),
      bytes = Buffer.from(id);
    const r = await call("POST", `/v1/assignments/${assignment}/uploads`, who, {
      id,
      files: [
        {
          id: file,
          name: "buildings.dbf",
          size: bytes.length,
          md5: md5(bytes),
        },
      ],
    });
    assert.equal(r.statusCode, 200, r.body);
    const row = (
      await pool.query("select * from firecheck_gateway.uploads where id=$1", [
        id,
      ])
    ).rows[0];
    return { id, file, bytes, who, folder: row.folder_id };
  }
  async function finish(batch: Awaited<ReturnType<typeof create>>) {
    const r = await call(
      "PUT",
      `/v1/uploads/${batch.id}/files/${batch.file}/chunks`,
      batch.who,
      batch.bytes,
      { "content-type": "application/octet-stream", "upload-offset": "0" },
    );
    assert.equal(r.statusCode, 200, r.body);
    const done = await call(
      "POST",
      `/v1/uploads/${batch.id}/complete`,
      batch.who,
    );
    assert.equal(done.statusCode, 200, done.body);
    return done.json();
  }
  const old = await create(worker);
  const recent = await create(worker);
  const colleague = await create(admin);
  await finish(recent);
  await finish(colleague);
  await finish(old); // A late old upload must not replace newer work.
  const top = await drive.children("output");
  assert.equal(top.length, 1);
  assert.equal(top[0]!.name, "Cebu");
  const current = await drive.children(top[0]!.id);
  const archive = current.find((f) => f.name === "Archive")!;
  assert.ok(
    current.some((f) => f.id === recent.folder && f.name.startsWith("Sam")),
  );
  assert.ok(
    current.some((f) => f.id === colleague.folder && f.name.startsWith("Alex")),
  );
  assert.ok(!current.some((f) => f.id === old.folder));
  assert.ok(
    (await drive.children(archive.id)).some((f) => f.id === old.folder),
  );
  const oldFile = (await drive.children(old.folder))[0]!;
  assert.deepEqual(drive.bytes.get(oldFile.id), old.bytes);
  const receipt = (await call("GET", `/v1/uploads/${old.id}`, worker)).json();
  assert.ok(receipt.folderPath.includes("/Archive/"));
  assert.ok(receipt.folderUrl.endsWith(old.folder));
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

test("failed copies and source mutation preserve last good publication; retry creates a fresh complete version", async () => {
  const before = (
    await pool.query(
      "select current_version from firecheck_gateway.sources where assignment_id=$1",
      [assignment],
    )
  ).rows[0].current_version;
  const count = Number(
    (await pool.query("select count(*) from firecheck_gateway.versions"))
      .rows[0].count,
  );
  const copy = drive.copy.bind(drive);
  let copied = 0;
  drive.copy = async (id, parent) => {
    if (copied++ === 1) throw new Error("controlled copy failure");
    return copy(id, parent);
  };
  try {
    assert.equal(
      (await call("POST", `/v1/admin/assignments/${assignment}/publish`, admin))
        .statusCode,
      503,
    );
    assert.equal(
      (
        await pool.query(
          "select current_version from firecheck_gateway.sources where assignment_id=$1",
          [assignment],
        )
      ).rows[0].current_version,
      before,
    );
    assert.equal(
      Number(
        (await pool.query("select count(*) from firecheck_gateway.versions"))
          .rows[0].count,
      ),
      count,
    );
  } finally {
    drive.copy = copy;
  }
  const source = (
    await pool.query(
      "select folder_id from firecheck_gateway.sources where assignment_id=$1",
      [assignment],
    )
  ).rows[0].folder_id;
  const file = (await drive.children(source))[0]!;
  const checksum = file.md5Checksum;
  drive.copy = async (id, parent) => {
    const result = await copy(id, parent);
    drive.files.get(file.id)!.md5Checksum = "f".repeat(32);
    return result;
  };
  try {
    const failed = await call(
      "POST",
      `/v1/admin/assignments/${assignment}/publish`,
      admin,
    );
    assert.equal(failed.statusCode, 409, failed.body);
    assert.equal(failed.json().code, "SOURCE_CHANGED_DURING_PUBLICATION");
    assert.equal(
      (
        await pool.query(
          "select current_version from firecheck_gateway.sources where assignment_id=$1",
          [assignment],
        )
      ).rows[0].current_version,
      before,
    );
  } finally {
    drive.copy = copy;
    drive.files.get(file.id)!.md5Checksum = checksum;
  }
  const retry = await call(
    "POST",
    `/v1/admin/assignments/${assignment}/publish`,
    admin,
  );
  assert.equal(retry.statusCode, 200, retry.body);
  assert.notEqual(retry.json().version, before);
  assert.equal(retry.json().files.length, 4);
  assert.equal(
    (
      await pool.query(
        "select current_version from firecheck_gateway.sources where assignment_id=$1",
        [assignment],
      )
    ).rows[0].current_version,
    retry.json().version,
  );
  assert.equal(
    (
      await call(
        "GET",
        `/v1/assignments/${assignment}/versions/${version}/files/${artifact}`,
      )
    ).statusCode,
    200,
  );
});

test("ordinary members cannot create, publish, enroll, remove, or register sources", async () => {
  for (const [method, path, body] of [
    ["POST", "/v1/admin/assignments", {}],
    ["POST", `/v1/admin/assignments/${assignment}/publish`, undefined],
    [
      "PUT",
      `/v1/admin/assignments/${assignment}/members/${outsider}`,
      undefined,
    ],
    [
      "DELETE",
      `/v1/admin/assignments/${assignment}/members/${worker}`,
      undefined,
    ],
    [
      "PUT",
      `/v1/admin/assignments/${assignment}/source`,
      { folderId: "input" },
    ],
  ] as const) {
    const response = await call(method, path, worker, body);
    assert.equal(
      response.statusCode,
      403,
      `${method} ${path}: ${response.body}`,
    );
    assert.equal(response.json().code, "SUPERVISOR_REQUIRED");
  }
  assert.equal(
    (
      await pool.query(
        "select 1 from public.assignment_members where assignment_id=$1 and enumerator_id=$2",
        [assignment, outsider],
      )
    ).rowCount,
    0,
  );
});

test("publication marks a fresh folder without listing the historical published root", async () => {
  const children = drive.children.bind(drive);
  drive.children = async (id) => {
    if (id === "published") throw new ApiError(413, "TOO_MANY_FILES");
    return children(id);
  };
  try {
    const result = await call(
      "POST",
      `/v1/admin/assignments/${assignment}/publish`,
      admin,
    );
    assert.equal(result.statusCode, 200, result.body);
    const folder = [...drive.files.values()].find(
      (f) => f.name === `${assignment}_${result.json().version}`,
    )!;
    assert.equal(
      folder.appProperties?.firecheckOutputKey,
      `source-publication:${assignment}:${result.json().version}`,
    );
  } finally {
    drive.children = children;
  }
});

test("reference snapshots retain incomplete resumable uploads and every historical version", async () => {
  const roots = ["input", "output", "published"];
  const snapshot = await publicationReferences(new Database(pool), roots);
  const uploads = (
    await pool.query("select folder_id from firecheck_gateway.uploads")
  ).rows;
  const versions = (
    await pool.query("select id from firecheck_gateway.versions")
  ).rows;
  assert.ok(uploads.length > 0);
  assert.ok(versions.length > 1);
  assert.ok(uploads.every((row) => snapshot.folderIds.includes(row.folder_id)));
  assert.ok(versions.every((row) => snapshot.versionIds.includes(row.id)));
  const repeated = await publicationReferences(new Database(pool), roots);
  assert.equal(snapshot.fingerprint, repeated.fingerprint);
  const source = (
    await pool.query(
      "select current_version from firecheck_gateway.sources where assignment_id=$1",
      [assignment],
    )
  ).rows[0];
  await pool.query(
    "update firecheck_gateway.sources set current_version=$2 where assignment_id=$1",
    [assignment, version],
  );
  try {
    assert.notEqual(
      (await publicationReferences(new Database(pool), roots)).fingerprint,
      snapshot.fingerprint,
    );
  } finally {
    await pool.query(
      "update firecheck_gateway.sources set current_version=$2 where assignment_id=$1",
      [assignment, source.current_version],
    );
  }
});
