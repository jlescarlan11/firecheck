/** Reorganize only gateway-owned output batches; never delete or rewrite data. */
import { readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { parseEnv } from "node:util";
import pg from "pg";
import { Database } from "../src/db.js";
import { driveFromEnvironment, descendant } from "../src/drive.js";
import { organizeOutput } from "../src/output-layout.js";

async function main() {
  const here = fileURLToPath(new URL("../", import.meta.url));
  const secrets = join(here, ".secrets");
  const folders = JSON.parse(
    await readFile(join(secrets, "drive-folders.json"), "utf8"),
  );
  const values = parseEnv(
    await readFile(join(secrets, "database.env"), "utf8"),
  );
  const uri = new URL(values.FIRECHECK_DATABASE_URL!);
  for (const key of ["sslmode", "sslcert", "sslrootcert", "sslkey"])
    uri.searchParams.delete(key);
  const pool = new pg.Pool({
    connectionString: uri.toString(),
    connectionTimeoutMillis: 10000,
    query_timeout: 30000,
    ssl: {
      ca: await readFile(join(secrets, "supabase-ca.crt"), "utf8"),
      rejectUnauthorized: true,
    },
  });
  const db = new Database(pool);
  const drive = await driveFromEnvironment({
    DRIVE_AUTH_MODE: "oauth",
    GOOGLE_OAUTH_BUNDLE_FILE: join(secrets, "drive/oauth.json"),
  });
  try {
    console.log("Checking output folder access");
    await descendant(
      drive,
      folders.DRIVE_OUTPUT_ROOT,
      folders.DRIVE_OUTPUT_ROOT,
    );
    console.log("Reading registered upload batches");
    const { rows } = await pool.query(
      "select * from firecheck_gateway.uploads order by assignment_id,user_id,created_at,id",
    );
    const legacy = process.argv.includes("--archive-legacy")
      ? (await drive.children(folders.DRIVE_OUTPUT_ROOT)).filter(
          (f) =>
            f.mimeType === "application/vnd.google-apps.folder" &&
            !f.appProperties?.firecheckOutputKey &&
            /^[^@\s]+@[^@\s]+$/.test(f.name),
        )
      : [];
    const plan = [];
    for (const row of rows) {
      await descendant(drive, row.folder_id, folders.DRIVE_OUTPUT_ROOT);
      plan.push({
        id: row.id,
        folderId: row.folder_id,
        assignment: row.assignment_id,
        user: row.user_id,
        complete: row.complete,
        previousPath: row.folder_path,
        previousMetadata: await drive.metadata(row.folder_id),
        files: (await drive.children(row.folder_id))
          .map((f) => ({ id: f.id, md5: f.md5Checksum, size: f.size }))
          .sort((a, b) => a.id.localeCompare(b.id)),
      });
    }
    console.log(
      JSON.stringify({
        batches: plan.length,
        legacyFolders: legacy.length,
        completed: plan.filter((p) => p.complete).length,
        apply: process.argv.includes("--apply"),
      }),
    );
    if (!process.argv.includes("--apply")) return;
    // Preserve a restricted local rollback manifest before any Drive moves.
    await writeFile(
      join(secrets, `output-layout-backup-${Date.now()}.json`),
      JSON.stringify({ batches: plan, legacyFolders: legacy }, null, 2),
      { mode: 0o600 },
    );
    for (const row of rows) {
      await db.transaction(async (client) => {
        // Refresh the row in case a pending upload has completed since discovery.
        const fresh = (
          await client.query(
            "select * from firecheck_gateway.uploads where id=$1",
            [row.id],
          )
        ).rows[0];
        await organizeOutput(client, drive, folders.DRIVE_OUTPUT_ROOT, fresh);
      });
    }
    for (const item of plan) {
      const files = (await drive.children(item.folderId))
        .map((f) => ({ id: f.id, md5: f.md5Checksum, size: f.size }))
        .sort((a, b) => a.id.localeCompare(b.id));
      if (JSON.stringify(files) !== JSON.stringify(item.files))
        throw new Error("File verification failed");
    }
    if (legacy.length) {
      await db.transaction(async (client) => {
        await client.query(
          "select pg_advisory_xact_lock(hashtextextended($1,0))",
          ["output:legacy"],
        );
        const archive = await drive.managedFolder(
          folders.DRIVE_OUTPUT_ROOT,
          "Archive",
          "legacy-outputs",
        );
        for (const folder of legacy) {
          const before = (await drive.children(folder.id))
            .map((f) => f.id)
            .sort();
          await drive.relocate(folder.id, archive.id, folder.name);
          const after = (await drive.children(folder.id))
            .map((f) => f.id)
            .sort();
          if (JSON.stringify(before) !== JSON.stringify(after))
            throw new Error("Legacy folder verification failed");
        }
      });
    }
    const top = await drive.children(folders.DRIVE_OUTPUT_ROOT);
    console.log(
      JSON.stringify({
        organized: rows.length,
        outputFolders: top.map((f) => ({ name: f.name, id: f.id })),
      }),
    );
  } finally {
    await pool.end();
  }
}
main().catch(() => {
  console.error("Output organization failed; existing files are preserved.");
  process.exitCode = 1;
});
