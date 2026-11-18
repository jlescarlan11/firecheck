/** Explicit read-only inventory. No apply/delete/move mode exists. */
import pg from "pg";
import { Database } from "../src/db.js";
import { driveFromEnvironment } from "../src/drive.js";
import {
  inventoryPublications,
  publicationReferences,
} from "../src/orphan-inventory.js";

if (process.argv.length !== 2)
  throw new Error("This command accepts no mutation flags");
const roots = [
  process.env.DRIVE_INPUT_ROOT,
  process.env.DRIVE_OUTPUT_ROOT,
  process.env.DRIVE_PUBLISHED_ROOT,
];
if (roots.some((root) => !root) || !process.env.DATABASE_URL)
  throw new Error("Explicit database and root configuration required");
const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  connectionTimeoutMillis: 10000,
  query_timeout: 30000,
});
try {
  const database = new Database(pool);
  const drive = await driveFromEnvironment();
  const report = await inventoryPublications(drive, roots[2]!, () =>
    publicationReferences(database, roots as string[]),
  );
  console.log(JSON.stringify(report, null, 2));
  if (report.status === "inconclusive") process.exitCode = 2;
} catch {
  console.error("Read-only inventory failed; no remote objects were modified.");
  process.exitCode = 1;
} finally {
  await pool.end();
}
