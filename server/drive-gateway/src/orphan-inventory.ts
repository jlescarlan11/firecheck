import type { Drive } from "./drive.js";
import { Database } from "./db.js";
import { hash } from "./domain.js";

export interface References {
  roots: string[];
  folderIds: string[];
  fileIds: string[];
  versionIds: string[];
  fingerprint?: string;
}
export interface InventoryEntry {
  folderId: string;
  classification: "protected" | "review-only";
  reason:
    | "retained-reference"
    | "unknown-provenance"
    | "possibly-in-flight-publication";
}
export interface InventoryReport {
  status: "complete" | "inconclusive";
  reason?: "references-changed" | "inspection-failed";
  entries: InventoryEntry[];
}
const signature = (refs: References) =>
  hash({
    roots: [...refs.roots].sort(),
    folderIds: [...refs.folderIds].sort(),
    fileIds: [...refs.fileIds].sort(),
    versionIds: [...refs.versionIds].sort(),
    fingerprint: refs.fingerprint,
  });

/** Report only. Absence from committed references cannot rule out an in-flight transaction. */
export async function inventoryPublications(
  drive: Pick<Drive, "metadata" | "children">,
  publishedRoot: string,
  readReferences: () => Promise<References>,
): Promise<InventoryReport> {
  try {
    const before = await readReferences();
    const protectedIds = new Set([...before.roots, ...before.folderIds]);
    // Derive retained folder identity from actual file parents; names are never ownership proof.
    for (const id of [...before.fileIds, ...before.folderIds]) {
      let current = id;
      const seen = new Set<string>();
      while (!before.roots.includes(current)) {
        if (seen.has(current) || seen.size >= 32)
          throw new Error("Invalid reference ancestry");
        seen.add(current);
        const file = await drive.metadata(current);
        if (file.trashed || file.parents?.length !== 1)
          throw new Error("Unresolved reference ancestry");
        current = file.parents[0]!;
        protectedIds.add(current);
      }
    }
    const folders = (await drive.children(publishedRoot))
      .filter((f) => f.mimeType === "application/vnd.google-apps.folder")
      .sort((a, b) => a.id.localeCompare(b.id));
    const entries: InventoryEntry[] = folders.map((folder) => {
      const key = folder.appProperties?.firecheckOutputKey ?? "";
      const marker =
        /^source-publication:([0-9a-f-]{36}):([0-9a-f-]{36})$/.exec(key);
      if (
        protectedIds.has(folder.id) ||
        (marker && before.versionIds.includes(marker[2]!))
      )
        return {
          folderId: folder.id,
          classification: "protected",
          reason: "retained-reference",
        };
      if (!marker)
        return {
          folderId: folder.id,
          classification: "protected",
          reason: "unknown-provenance",
        };
      return {
        folderId: folder.id,
        classification: "review-only",
        reason: "possibly-in-flight-publication",
      };
    });
    const after = await readReferences();
    if (signature(before) !== signature(after))
      return {
        status: "inconclusive",
        reason: "references-changed",
        entries: [],
      };
    return {
      status: entries.some((e) => e.classification === "review-only")
        ? "inconclusive"
        : "complete",
      entries,
    };
  } catch {
    // Listing overflow and missing metadata must never leave a partial review candidate list.
    return { status: "inconclusive", reason: "inspection-failed", entries: [] };
  }
}

/** Each read is internally consistent; inventory compares two independent committed snapshots. */
export async function publicationReferences(
  database: Database,
  roots: string[],
): Promise<References> {
  return database.transaction(async (db) => {
    await db.query("set transaction isolation level repeatable read read only");
    const sources = (
      await db.query(
        "select * from firecheck_gateway.sources order by assignment_id",
      )
    ).rows;
    const versions = (
      await db.query("select * from firecheck_gateway.versions order by id")
    ).rows;
    const uploads = (
      await db.query("select * from firecheck_gateway.uploads order by id")
    ).rows;
    const files = (
      await db.query("select * from firecheck_gateway.upload_files order by upload_id,id")
    ).rows;
    const exists = (
      await db.query(
        "select to_regclass('firecheck_sync.exports') as exports,to_regclass('firecheck_sync.export_jobs') as jobs",
      )
    ).rows[0];
    const exports = exists.exports
      ? (
          await db.query(
            "select * from firecheck_sync.exports order by assignment_id,revision",
          )
        ).rows
      : [];
    const jobs = exists.jobs
      ? (
          await db.query(
            "select * from firecheck_sync.export_jobs order by assignment_id",
          )
        ).rows
      : [];
    return {
      roots,
      folderIds: [
        ...sources.map((s) => s.folder_id),
        ...uploads.map((u) => u.folder_id),
        ...exports.map((e) => e.manifest.folderId),
      ].filter(Boolean),
      fileIds: [
        ...versions.flatMap((v) =>
          v.manifest.map((f: { driveId: string }) => f.driveId),
        ),
        ...files.map((f) => f.drive_id),
      ].filter(Boolean),
      versionIds: versions.map((v) => v.id),
      fingerprint: hash({ sources, versions, uploads, files, exports, jobs }),
    };
  });
}
