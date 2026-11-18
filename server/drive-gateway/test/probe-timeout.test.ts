import { test } from "node:test";
import { strict as assert } from "node:assert";
import { randomUUID } from "node:crypto";
import { promisify } from "node:util";
import { execFile } from "node:child_process";
import pg from "pg";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
const run = promisify(execFile);
test("runner survives a real idle transaction abort, stops copies and retains last-good-pointer evidence", async () => {
  const url = new URL(
    process.env.TEST_DATABASE_URL ??
      "postgresql://postgres:local-sync-test@127.0.0.1:55441/postgres",
  );
  assert.equal(url.hostname, "127.0.0.1");
  assert.equal(url.port, "55441");
  assert.equal(url.pathname, "/postgres");
  const name = `probe_timeout_${randomUUID().replaceAll("-", "")}`;
  const admin = new pg.Pool({ connectionString: url.toString() });
  let fixture: pg.Pool | undefined;
  const evidenceDirectory = await mkdtemp(
    join(tmpdir(), "firecheck-probe-timeout-"),
  );
  const evidencePath = join(evidenceDirectory, "proof.json");
  try {
    await admin.query(`create database ${name}`);
    url.pathname = "/" + name;
    fixture = new pg.Pool({ connectionString: url.toString() });
    await fixture.query(
      "create table versions(id text primary key);insert into versions values('last-good');create table sources(current_version text references versions(id));insert into sources values('last-good')",
    );
    const result = await run(
      process.execPath,
      ["--import", "tsx", "test/probe-timeout-child.ts"],
      {
        env: {
          ...process.env,
          PROBE_TIMEOUT_DATABASE_URL: url.toString(),
          PROBE_TIMEOUT_EVIDENCE_PATH: evidencePath,
        },
        timeout: 10000,
      },
    );
    const proof = JSON.parse(result.stdout.trim());
    assert.deepEqual(JSON.parse(await readFile(evidencePath, "utf8")), proof);
    assert.equal(proof.caught, true);
    assert.equal(proof.caughtSqlState, "25P03");
    assert.equal(proof.settled, true);
    assert.equal(proof.releasedBeforeSettled, false);
    assert.equal(proof.copies, 1);
    assert.deepEqual(proof.source, { current_version: "last-good" });
    assert.deepEqual(proof.versions, [{ id: "last-good" }]);
    assert.equal(proof.evidence.sqlState, "25P03");
    assert.equal(proof.afterLaterEvent.sqlState, "25P03");
    assert.equal(result.stderr, "");
  } finally {
    await fixture?.end();
    await admin.query(`drop database if exists ${name}`);
    await admin.end();
    await rm(evidenceDirectory, { recursive: true });
  }
});
