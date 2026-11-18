import type { Db } from "./db.js";
import type { Drive } from "./drive.js";

const label = (value: string) =>
  value
    .replace(/[\\/\x00-\x1f]/g, "_")
    .trim()
    .slice(0, 100);

/** Caller holds the assignment advisory lock throughout folder changes. */
export async function outputLayout(
  db: Db,
  drive: Drive,
  root: string,
  assignment: string,
  user: string,
) {
  const { rows } = await db.query(
    `select a.name,e.display_name from public.assignments a cross join public.enumerators e where a.id=$1 and e.id=$2`,
    [assignment, user],
  );
  if (!rows[0]) throw new Error("Missing upload identity");
  const map = await drive.managedFolder(
    root,
    label(rows[0].name || "Map"),
    `map:${assignment}`,
  );
  const archive = await drive.managedFolder(
    map.id,
    "Archive",
    `archive:${assignment}`,
  );
  // Short identity suffix distinguishes collaborators who have the same name.
  const person = `${label(rows[0].display_name || "Surveyor")} (${user.slice(0, 8)})`;
  return { map, archive, person, path: `firecheck/output/${map.name}/` };
}

export function archivedName(upload: any, person: string) {
  const date = new Date(upload.created_at)
    .toISOString()
    .replace(/[T:]/g, "-")
    .slice(0, 19);
  return `${person} - ${date} - ${upload.id.slice(0, 8)}`;
}

/** Promote only a fully confirmed batch. Prior batches keep their folder/file IDs. */
export async function organizeOutput(
  db: Db,
  drive: Drive,
  root: string,
  upload: any,
) {
  await db.query("select pg_advisory_xact_lock(hashtextextended($1,0))", [
    `output:${upload.assignment_id}`,
  ]);
  const layout = await outputLayout(
    db,
    drive,
    root,
    upload.assignment_id,
    upload.user_id,
  );
  const { rows: history } = await db.query(
    `select * from firecheck_gateway.uploads where assignment_id=$1 and user_id=$2 and complete=true order by created_at desc,id desc`,
    [upload.assignment_id, upload.user_id],
  );
  const candidates = [upload, ...history.filter((u) => u.id !== upload.id)];
  const latest = candidates
    .filter((u) => u.complete)
    .sort(
      (a, b) =>
        new Date(b.created_at).getTime() - new Date(a.created_at).getTime() ||
        b.id.localeCompare(a.id),
    )[0];
  // Archive before promoting, so there is only one visible latest folder.
  for (const row of candidates.filter((u) => u.id !== latest?.id)) {
    const name = archivedName(row, layout.person);
    const path = `${layout.path}Archive/${name}/`;
    if (row.folder_path === path) continue;
    await drive.relocate(row.folder_id, layout.archive.id, name);
    await db.query(
      "update firecheck_gateway.uploads set folder_path=$2 where id=$1",
      [row.id, path],
    );
    if (row.id === upload.id) upload.folder_path = path;
  }
  if (latest) {
    const path = `${layout.path}${layout.person}/`;
    if (latest.folder_path !== path)
      await drive.relocate(latest.folder_id, layout.map.id, layout.person);
    await db.query(
      "update firecheck_gateway.uploads set folder_path=$2 where id=$1",
      [latest.id, path],
    );
    if (latest.id === upload.id) upload.folder_path = path;
  }
}
