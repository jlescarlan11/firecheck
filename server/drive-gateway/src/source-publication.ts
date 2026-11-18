import { randomUUID } from "node:crypto";
import type { Db } from "./db.js";
import { assert, hash, validateMap, type Artifact } from "./domain.js";
import { artifact, descendant, type Drive } from "./drive.js";

/** Caller owns the transaction; the current pointer changes only after every copy verifies. */
export async function publishSource(
  db: Db,
  drive: Drive,
  config: { inputRoot: string; publishedRoot: string; sharedDrive?: string },
  id: string,
  actor: string,
) {
  const schema = await db.query(
    "select to_regclass('firecheck_sync.maps') present",
  );
  if (schema.rows[0].present) {
    const { rows } = await db.query(
      "select enabled from firecheck_sync.maps where assignment_id=$1",
      [id],
    );
    assert(!rows[0]?.enabled, 409, "SHARED_MAP_USE_SERVER_IMPORT");
  }
  const source = (
    await db.query(
      "select * from firecheck_gateway.sources where assignment_id=$1 for update",
      [id],
    )
  ).rows[0];
  assert(source, 404, "SOURCE_NOT_REGISTERED");
  await descendant(
    drive,
    source.folder_id,
    config.inputRoot,
    config.sharedDrive,
  );
  const list = async () =>
    (await drive.children(source.folder_id))
      .filter(
        (f) =>
          /\.(shp|shx|dbf|prj)$/i.test(f.name) ||
          ["field_requirements.txt", "form_definition.json"].includes(
            f.name.toLowerCase(),
          ),
      )
      .sort((a, b) => a.id.localeCompare(b.id));
  const before = await list();
  for (const f of before)
    assert(
      f.mimeType !== "application/vnd.google-apps.shortcut",
      400,
      "SHORTCUT_NOT_ALLOWED",
    );
  validateMap(before.map(artifact));
  const version = randomUUID();
  const folder = await drive.folder(
    config.publishedRoot,
    `${id}_${version}`,
    `source-publication:${id}:${version}`,
  );
  const files: Artifact[] = [];
  for (const f of before) files.push(artifact(await drive.copy(f.id, folder)));
  validateMap(files);
  assert(
    hash(before) === hash(await list()),
    409,
    "SOURCE_CHANGED_DURING_PUBLICATION",
  );
  for (let i = 0; i < files.length; i++)
    assert(
      files[i]!.md5 === before[i]!.md5Checksum &&
        files[i]!.size === Number(before[i]!.size),
      409,
      "SOURCE_CHANGED_DURING_PUBLICATION",
    );
  await db.query(
    "insert into firecheck_gateway.versions(id,assignment_id,manifest,manifest_hash,published_by) values($1,$2,$3,$4,$5)",
    [version, id, JSON.stringify(files), hash(files), actor],
  );
  await db.query(
    "update firecheck_gateway.sources set current_version=$2 where assignment_id=$1",
    [id, version],
  );
  return { version, files };
}
