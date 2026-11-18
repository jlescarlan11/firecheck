import { test } from "node:test";
import { strict as assert } from "node:assert";
import { organizeOutput } from "../src/output-layout.js";
import type { Db } from "../src/db.js";
import { SharedTestDrive } from "./shared-drive-fixture.js";
test("equal creation times use stable batch IDs and late completion preserves receipt folder identity", async () => {
  const drive = new SharedTestDrive();
  const assignment = "00000000-0000-0000-0000-000000000001";
  const user = "00000000-0000-0000-0000-000000000002";
  const make = (id: string) => ({
    id,
    assignment_id: assignment,
    user_id: user,
    complete: true,
    folder_id: `folder-${id}`,
    folder_path: "pending",
    created_at: "2026-11-18T00:00:00Z",
  });
  const older = make("00000000-0000-0000-0000-000000000003");
  const newest = make("00000000-0000-0000-0000-000000000004");
  for (const batch of [older, newest])
    drive.files.set(batch.folder_id, {
      id: batch.folder_id,
      name: "pending",
      mimeType: "application/vnd.google-apps.folder",
      parents: ["output"],
    });
  const queries: string[] = [];
  const db = {
    query: async (sql: string, values?: unknown[]) => {
      queries.push(sql);
      if (sql.includes("a.name,e.display_name"))
        return { rows: [{ name: "Map", display_name: "Surveyor" }] };
      if (sql.includes("complete=true")) return { rows: [older, newest] };
      if (sql.startsWith("update firecheck_gateway.uploads")) {
        const batch = [older, newest].find((batch) => batch.id === values![0])!;
        batch.folder_path = values![1] as string;
      }
      return { rows: [] };
    },
  } as unknown as Db;
  await organizeOutput(db, drive, "output", older);
  const currentMap = [...drive.files.values()].find(
    (file) => file.appProperties?.firecheckOutputKey === `map:${assignment}`,
  )!;
  const archive = [...drive.files.values()].find(
    (file) =>
      file.appProperties?.firecheckOutputKey === `archive:${assignment}`,
  )!;
  assert.deepEqual((await drive.metadata(newest.folder_id)).parents, [
    currentMap.id,
  ]);
  assert.deepEqual((await drive.metadata(older.folder_id)).parents, [
    archive.id,
  ]);
  assert.ok(older.folder_path.includes("/Archive/"));
  const identities = [...drive.files.keys()].sort();
  await organizeOutput(db, drive, "output", older);
  assert.deepEqual([...drive.files.keys()].sort(), identities);
  assert.deepEqual((await drive.metadata(newest.folder_id)).parents, [
    currentMap.id,
  ]);
  assert.equal(
    queries[0],
    "select pg_advisory_xact_lock(hashtextextended($1,0))",
  );
});
