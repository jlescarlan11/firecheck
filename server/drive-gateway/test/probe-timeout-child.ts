/** Child-process fixture: an unhandled checked-out-client error must fail the parent regression. */
import pg from "pg";
import { writeFile } from "node:fs/promises";
import { ProbeDatabase } from "../tools/probe-database.js";
const url = new URL(process.env.PROBE_TIMEOUT_DATABASE_URL!);
if (
  url.hostname !== "127.0.0.1" ||
  url.port !== "55441" ||
  !/^\/probe_timeout_[a-z0-9]+$/.test(url.pathname)
)
  throw new Error("Disposable local timeout fixture required");
const pool = new pg.Pool({ connectionString: url.toString(), max: 1 });
const database = new ProbeDatabase(pool);
let copies = 0,
  settled = false,
  releasedBeforeSettled = false;
pool.on("release", () => {
  if (!settled) releasedBeforeSettled = true;
});
let caught = false;
let caughtSqlState: string | undefined;
try {
  await database.transaction(async (client) => {
    await client.query("insert into versions values('candidate')");
    await client.query("update sources set current_version='candidate'");
    await client.query("set local idle_in_transaction_session_timeout='100ms'");
    try {
      database.assertHealthy();
      copies++;
      // Represent one accepted, bounded Drive operation while PostgreSQL terminates the idle transaction.
      await new Promise((resolve) => setTimeout(resolve, 300));
      database.assertHealthy();
      copies++;
    } finally {
      settled = true;
    }
  });
} catch (error) {
  caught = true;
  caughtSqlState = (error as { code?: string }).code;
}
const inspector = new pg.Pool({ connectionString: url.toString() });
const source = (await inspector.query("select current_version from sources"))
  .rows[0];
const versions = (await inspector.query("select id from versions order by id"))
  .rows;
const evidence = database.failureEvidence();
// A later termination event must not replace the first SQLSTATE or throw from an event handler.
pool.emit("error", new Error("later connection termination"));
const proof = {
  caught,
  caughtSqlState,
  copies,
  settled,
  releasedBeforeSettled,
  source,
  versions,
  evidence,
  afterLaterEvent: database.failureEvidence(),
};
await writeFile(
  process.env.PROBE_TIMEOUT_EVIDENCE_PATH!,
  JSON.stringify(proof),
  { flag: "wx", mode: 0o600 },
);
console.log(JSON.stringify(proof));
await pool.end();
await inspector.end();
