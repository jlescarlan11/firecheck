/** Append-only, private My Drive + uniquely named loopback-Postgres development measurement. */
import { randomUUID, createHash } from "node:crypto";
import { mkdir, readFile, writeFile, rename } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { performance } from "node:perf_hooks";
import pg from "pg";
import { buildApp } from "../src/app.js";
import { ProbeDatabase } from "./probe-database.js";
import { ApiError, CHUNK_SIZE, hash } from "../src/domain.js";
import { driveFromEnvironment, type Drive } from "../src/drive.js";
import {
  capacityFixture,
  localProbeDatabase,
  retainedPayloadBound,
} from "../src/development-probe.js";

const fixture = capacityFixture();
const plan = {
  mode: "append-only-private-development",
  parent: "authenticated My Drive root",
  fileCount: fixture.length,
  sourceBytes: fixture.reduce((n, f) => n + f.size, 0),
  retainedPayloadBytesMaximum: retainedPayloadBound(fixture),
  failedCopyBytesMaximum: 64,
  publicationSafetyBudgetMs: 150000,
  hostedRuntimeVerified: false,
  gisPayloadValid: false,
  mutations: [
    "one new private sandbox and input/output/published children",
    "100 opaque source files",
    "first publication",
    "one 64-byte failed publication copy",
    "fresh retry publication",
    "one unique disposable local database",
  ],
  forbidden: [
    "sharing changes",
    "remote deletion/trashing/moves",
    "shared field root writes",
    "deployment",
    "production database",
    "orphan inventory execution",
  ],
};
if (process.argv.length === 2) {
  console.log(JSON.stringify(plan, null, 2));
} else if (process.argv.length === 3 && process.argv[2] === "--execute") {
  await execute();
} else {
  throw new Error(
    "Use no arguments for the read-only plan, or --execute for the reviewed development probe",
  );
}

async function execute() {
  const id = randomUUID();
  const databaseName = `firecheck_devprobe_${id.replaceAll("-", "")}`;
  const adminUrl = process.env.DEV_PROBE_DATABASE_URL;
  if (
    !adminUrl ||
    !process.env.GOOGLE_OAUTH_BUNDLE_FILE ||
    !process.env.DEV_PROBE_MANIFEST
  )
    throw new Error(
      "Explicit loopback database, OAuth bundle and unique local manifest path are required",
    );
  const databaseUrl = localProbeDatabase(adminUrl, databaseName); // Refuse non-designated DB before writes.
  const manifestPath = resolve(process.env.DEV_PROBE_MANIFEST);
  await mkdir(dirname(manifestPath), { recursive: true, mode: 0o700 });
  const manifest: any = {
    id,
    startedAt: new Date().toISOString(),
    plan,
    databaseName,
    runtime: {
      node: process.version,
      platform: process.platform,
      arch: process.arch,
      driveRequestTimeoutMs: 60000,
      databaseLockTimeoutMs: 3000,
      databaseIdleTransactionTimeoutMs: 120000,
      fastifyRequestReceiveTimeoutMs: 90000,
    },
    status: "preparing",
    folders: [],
    createdFiles: [],
    sources: [],
    calls: [],
    publications: [],
    limits:
      "Actual Google Drive + local PostgreSQL + Node/Fastify injection only. Synthetic authentication and standalone gateway schema. No hosted capacity or mobile GIS validity claim.",
  };
  await writeFile(manifestPath, JSON.stringify(manifest, null, 2), {
    flag: "wx",
    mode: 0o600,
  });
  const save = async () => {
    const temporary = `${manifestPath}.tmp`;
    await writeFile(temporary, JSON.stringify(manifest, null, 2), {
      mode: 0o600,
    });
    await rename(temporary, manifestPath);
  };
  const admin = new pg.Pool({
    connectionString: adminUrl,
    connectionTimeoutMillis: 10000,
  });
  let pool: pg.Pool | undefined;
  let probeDatabase: ProbeDatabase | undefined;
  let app: ReturnType<typeof buildApp> | undefined;
  let activePublication:
    { started: number; failAfterFirst: boolean; copies: number } | undefined;
  try {
    const actual = await driveFromEnvironment({
      DRIVE_AUTH_MODE: "oauth",
      GOOGLE_OAUTH_BUNDLE_FILE: process.env.GOOGLE_OAUTH_BUNDLE_FILE,
    });
    const quota = await actual.storageQuota();
    if (
      !quota.limit ||
      !/^\d+$/.test(quota.limit) ||
      !/^\d+$/.test(quota.usage) ||
      BigInt(quota.limit) - BigInt(quota.usage) < BigInt(4 * 1024 ** 3)
    )
      throw new ApiError(409, "DEV_PROBE_INSUFFICIENT_KNOWN_QUOTA");
    manifest.quotaBefore = quota;
    const drive = new Proxy(actual, {
      get(target, property, receiver) {
        const value = Reflect.get(target, property, receiver);
        if (typeof value !== "function") return value;
        return async (...args: any[]) => {
          const publication = activePublication;
          const budgetCheck = () => {
            probeDatabase?.assertHealthy();
            if (
              publication &&
              performance.now() - publication.started >=
                plan.publicationSafetyBudgetMs
            )
              throw new ApiError(503, "DEV_PROBE_PUBLICATION_BUDGET_EXCEEDED");
          };
          budgetCheck();
          if (
            property === "copy" &&
            publication?.failAfterFirst &&
            publication.copies === 1
          )
            throw new ApiError(503, "CONTROLLED_DEV_PROBE_COPY_FAILURE");
          const started = performance.now();
          try {
            const result = await value.apply(target, args);
            if (property === "folder") {
              manifest.folders.push({
                id: result,
                parent: args[0],
                name: args[1],
                marker: args[2],
              });
              await save();
            }
            if (property === "empty" || property === "copy") {
              manifest.createdFiles.push({
                id: property === "empty" ? result : result.id,
                parent: args[property === "empty" ? 0 : 1],
                kind: property,
              });
              if (property === "copy" && publication) publication.copies++;
              await save();
            }
            budgetCheck();
            return result;
          } finally {
            // Never record arguments, bearer tokens or resumable URLs.
            manifest.calls.push({
              method: String(property),
              milliseconds: performance.now() - started,
              phase: publication ? "publication" : "setup",
            });
          }
        };
      },
    }) as typeof actual;
    // Write only this freshly generated DB name on the designated local container.
    await admin.query(`create database ${databaseName}`);
    pool = new pg.Pool({ connectionString: databaseUrl });
    await pool.query(`do $$ begin
      if not exists(select 1 from pg_roles where rolname='anon') then create role anon;end if;
      if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated;end if;
      end $$;
      create schema auth; create function auth.uid() returns uuid language sql as $$ select null::uuid $$;
      create table public.enumerators(id uuid primary key,display_name text default 'Development probe');
      create table public.assignments(id uuid primary key,name text,closed_remotely boolean default false);
      create table public.assignment_members(assignment_id uuid references public.assignments(id),enumerator_id uuid references public.enumerators(id),role text,primary key(assignment_id,enumerator_id));
      create table public.drive_uploads(id uuid primary key,assignment_id uuid,uploaded_by uuid,drive_folder_path text,drive_folder_url text,file_count int);
      alter table public.assignments enable row level security;
      alter table public.assignment_members enable row level security;
      alter table public.enumerators enable row level security;
      alter table public.drive_uploads enable row level security;
      create function public.claim_assignment_by_name(text) returns uuid language sql as $$ select null::uuid $$;
      create function public.resolve_assignment_id_by_name(text) returns uuid language sql as $$ select null::uuid $$;`);
    await pool.query(
      await readFile(
        new URL(
          "../../../supabase/migrations/20260915151740_drive_gateway.sql",
          import.meta.url,
        ),
        "utf8",
      ),
    );
    manifest.postgresVersion = (
      await pool.query("select version() as version")
    ).rows[0].version;
    const supervisor = randomUUID(),
      assignment = randomUUID();
    manifest.assignment = assignment;
    await pool.query("insert into public.enumerators(id) values($1)", [
      supervisor,
    ]);
    await pool.query("insert into public.assignments(id,name) values($1,$2)", [
      assignment,
      `Private capacity probe ${id}`,
    ]);
    await pool.query(
      "insert into public.assignment_members values($1,$2,'owner')",
      [assignment, supervisor],
    );
    await pool.query("insert into firecheck_gateway.supervisors values($1)", [
      supervisor,
    ]);
    await pool.query(
      await readFile(new URL("../sql/activate.sql", import.meta.url), "utf8"),
    );
    manifest.sandboxId = await drive.folder(
      "root",
      `FireCheck private development publication ${id}`,
      `devprobe:${id}`,
    );
    await save(); // Stable sandbox identity is durable before access inspection/payload writes.
    const verifyPrivate = async (folderId: string) => {
      const access = await drive.folderAccess(folderId);
      if (
        !access.ownedByMe ||
        access.permissions.length !== 1 ||
        access.permissions[0]?.type !== "user" ||
        access.permissions[0]?.role !== "owner" ||
        access.permissions[0]?.deleted
      )
        throw new ApiError(409, "DEV_PROBE_SANDBOX_NOT_OWNER_ONLY");
      return { folderId, ownedByMe: true, ownerOnly: true };
    };
    manifest.access = [await verifyPrivate(manifest.sandboxId)];
    const roots: Record<string, string> = {};
    for (const name of ["input", "output", "published"]) {
      roots[name] = await drive.folder(
        manifest.sandboxId,
        name,
        `devprobe:${id}:${name}`,
      );
      manifest.access.push(await verifyPrivate(roots[name]!));
    }
    manifest.roots = roots;
    await save();
    const sourceStarted = performance.now();
    // Allocate stable IDs first so publication's ID ordering copies the 64-byte file first.
    const allocated = [];
    for (const file of fixture)
      allocated.push({
        id: await drive.empty(roots.input!, file.name),
        name: file.name,
      });
    allocated.sort((a, b) => a.id.localeCompare(b.id));
    for (let index = 0; index < allocated.length; index++) {
      const file = allocated[index]!,
        spec = fixture[index]!;
      const digest = createHash("md5");
      const session = await drive.begin(file.id, spec.size);
      for (let offset = 0; offset < spec.size; offset += CHUNK_SIZE) {
        const bytes = Buffer.alloc(
          Math.min(CHUNK_SIZE, spec.size - offset),
          spec.byte,
        );
        digest.update(bytes);
        await drive.chunk(session, bytes, offset, spec.size);
      }
      const checksum = digest.digest("hex"),
        meta = await drive.metadata(file.id);
      if (meta.md5Checksum !== checksum || Number(meta.size) !== spec.size)
        throw new ApiError(409, "DEV_PROBE_SOURCE_MISMATCH");
      manifest.sources.push({ ...file, size: spec.size, md5: checksum });
      await save();
    }
    manifest.sourceUploadMilliseconds = performance.now() - sourceStarted;
    const routePool = new pg.Pool({
      connectionString: databaseUrl,
      options: "-c role=firecheck_gateway_server",
    });
    probeDatabase = new ProbeDatabase(routePool);
    app = buildApp({
      database: probeDatabase,
      drive: drive as Drive,
      config: {
        inputRoot: roots.input!,
        outputRoot: roots.output!,
        publishedRoot: roots.published!,
      },
      authenticate: async (token) => {
        if (token !== supervisor) throw new ApiError(401, "SESSION_EXPIRED");
        return supervisor;
      },
    });
    app.addHook("onClose", async () => {
      await routePool.end();
    });
    const call = (method: "GET" | "PUT" | "POST", url: string, body?: any) =>
      app!.inject({
        method,
        url,
        headers: { authorization: `Bearer ${supervisor}` },
        payload: body,
      });
    const registration = await call(
      "PUT",
      `/v1/admin/assignments/${assignment}/source`,
      { folderId: roots.input },
    );
    if (registration.statusCode !== 200)
      throw new ApiError(503, "DEV_PROBE_REGISTRATION_FAILED");
    const publish = async (name: string, failAfterFirst: boolean) => {
      activePublication = {
        started: performance.now(),
        failAfterFirst,
        copies: 0,
      };
      const started = activePublication.started;
      const response = await call(
        "POST",
        `/v1/admin/assignments/${assignment}/publish`,
      );
      const copies = activePublication.copies;
      activePublication = undefined;
      const body = response.json();
      manifest.publications.push({
        name,
        statusCode: response.statusCode,
        milliseconds: performance.now() - started,
        copies,
        response: body,
      });
      await save();
      return { response, body, copies };
    };
    const first = await publish("first-complete", false);
    if (first.response.statusCode !== 200)
      throw new ApiError(
        503,
        first.body.code ?? "DEV_PROBE_FIRST_PUBLICATION_FAILED",
      );
    const verifyVersion = async (version: string) => {
      const row = (
        await pool!.query(
          "select manifest,manifest_hash from firecheck_gateway.versions where id=$1",
          [version],
        )
      ).rows[0];
      if (
        !row ||
        row.manifest.length !== 100 ||
        row.manifest_hash !==
          hash(
            row.manifest.map((f: any) => ({
              id: f.id,
              name: f.name,
              size: f.size,
              md5: f.md5,
              driveId: f.driveId,
            })),
          )
      )
        throw new ApiError(409, "DEV_PROBE_MANIFEST_MISMATCH");
      for (let i = 0; i < row.manifest.length; i++) {
        const file = row.manifest[i],
          source = manifest.sources[i];
        const meta = await drive.metadata(file.driveId);
        if (
          file.name !== source.name ||
          file.size !== source.size ||
          file.md5 !== source.md5 ||
          Number(meta.size) !== file.size ||
          meta.md5Checksum !== file.md5
        )
          throw new ApiError(409, "DEV_PROBE_COPY_MISMATCH");
      }
      return row.manifest;
    };
    const firstFiles = await verifyVersion(first.body.version);
    const failed = await publish("controlled-failure-after-64-bytes", true);
    const current = async () =>
      (
        await pool!.query(
          "select current_version from firecheck_gateway.sources where assignment_id=$1",
          [assignment],
        )
      ).rows[0].current_version;
    const oldDownload = await call(
      "GET",
      `/v1/assignments/${assignment}/versions/${first.body.version}/files/${firstFiles[0].id}`,
    );
    manifest.failureProof = {
      currentVersion: await current(),
      retainedVersionDownloadStatus: oldDownload.statusCode,
      retainedVersionDownloadBytes: oldDownload.rawPayload.length,
      committedVersionCount: Number(
        (await pool.query("select count(*) from firecheck_gateway.versions"))
          .rows[0].count,
      ),
    };
    if (
      failed.response.statusCode !== 503 ||
      failed.body.code !== "CONTROLLED_DEV_PROBE_COPY_FAILURE" ||
      failed.copies !== 1 ||
      manifest.failureProof.currentVersion !== first.body.version ||
      oldDownload.statusCode !== 200 ||
      oldDownload.rawPayload.length !== 64 ||
      manifest.failureProof.committedVersionCount !== 1
    )
      throw new ApiError(409, "DEV_PROBE_FAILURE_ATOMICITY_MISMATCH");
    const retry = await publish("fresh-complete-retry", false);
    if (
      retry.response.statusCode !== 200 ||
      retry.body.version === first.body.version ||
      (await current()) !== retry.body.version
    )
      throw new ApiError(409, "DEV_PROBE_RETRY_FAILED");
    await verifyVersion(retry.body.version);
    await verifyVersion(first.body.version);
    manifest.versionBindings = (
      await pool.query(
        "select * from firecheck_gateway.versions order by published_at,id",
      )
    ).rows;
    manifest.quotaAfter = await actual.storageQuota();
    manifest.status = "complete-development-measurement";
    manifest.finishedAt = new Date().toISOString();
    manifest.databaseCleanup =
      "pending; proof saved before dropping only this unique local database";
    await save();
    await app.close();
    app = undefined;
    await pool.end();
    pool = undefined;
    await admin.query(`drop database ${databaseName}`);
    manifest.databaseCleanup =
      "dropped unique local probe database after preserving evidence";
    await save();
    console.log(
      JSON.stringify(
        {
          status: manifest.status,
          sandboxId: manifest.sandboxId,
          manifestPath,
          publications: manifest.publications.map((p: any) => ({
            name: p.name,
            statusCode: p.statusCode,
            milliseconds: p.milliseconds,
            copies: p.copies,
          })),
        },
        null,
        2,
      ),
    );
  } catch (error) {
    activePublication = undefined;
    manifest.status = "failed-or-boundary-observed";
    manifest.databaseFailure = probeDatabase?.failureEvidence();
    manifest.failureCode =
      error instanceof ApiError
        ? error.code
        : "DEV_PROBE_FAILED_REVIEW_RETAINED_MANIFEST";
    manifest.databaseCleanup =
      "retained if created; no remote cleanup performed";
    manifest.finishedAt = new Date().toISOString();
    if (pool && manifest.assignment) {
      try {
        manifest.failureDatabaseState = {
          sources: (await pool.query("select * from firecheck_gateway.sources"))
            .rows,
          versions: (
            await pool.query(
              "select * from firecheck_gateway.versions order by id",
            )
          ).rows,
        };
      } catch {
        manifest.failureDatabaseState = "unavailable";
      }
    }
    await save();
    console.error(
      JSON.stringify({
        status: manifest.status,
        failureCode: manifest.failureCode,
        manifestPath,
        sandboxId: manifest.sandboxId,
      }),
    );
    process.exitCode = 1;
  } finally {
    await app?.close();
    await pool?.end();
    await admin.end();
  }
}
