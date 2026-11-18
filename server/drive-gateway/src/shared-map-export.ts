import { randomUUID, createHash } from "node:crypto";
import { Buffer } from "node:buffer";
import { Database } from "./db.js";
import type { Drive } from "./drive.js";
import { artifact } from "./drive.js";
import { ApiError } from "./domain.js";

export interface SharedSnapshot {
  schema_version: 1;
  assignment_id: string;
  revision: number;
  assignment: Record<string, unknown>;
  features: Array<Record<string, any>>;
}

/** Public GIS projection deliberately excludes household responses and photos.
 * The native shared package is also membership-scoped and excludes household PII.
 */
export function geoJson(snapshot: SharedSnapshot) {
  return {
    type: "FeatureCollection",
    assignment_id: snapshot.assignment_id,
    revision: snapshot.revision,
    features: snapshot.features
      .filter((f) => !f.deleted && !f.pending_dedup)
      .map((f) => ({
        type: "Feature",
        id: f.id,
        geometry: f.geometry_geojson,
        properties: {
          feature_id: f.id,
          feature_type: f.feature_type,
          split_from_id: f.split_from_id,
          merged_into_id: f.merged_into_id,
          surveys: (f.submissions ?? []).map((s: any) => ({
            id: s.id,
            form_version: s.form_version,
            // Free-text remarks, identifiers and photos are not public export fields.
            building: s.attribute_values?.building
              ? {
                  ra_9514_type: s.attribute_values.building.ra_9514_type,
                  storeys: s.attribute_values.building.storeys,
                  material: s.attribute_values.building.material,
                }
              : null,
            road: s.attribute_values?.road
              ? {
                  is_bridge: s.attribute_values.road.is_bridge,
                  width_meters: s.attribute_values.road.width_meters,
                }
              : null,
          })),
        },
      })),
  };
}
const maxBytes = 16 * 1024 * 1024;
export async function writeVerified(
  drive: Drive,
  parent: string,
  name: string,
  bytes: Buffer,
  existingId?: string,
) {
  if (bytes.length > maxBytes)
    throw new ApiError(413, "SHARED_EXPORT_TOO_LARGE");
  const checksum = createHash("md5").update(bytes).digest("hex");
  const existing = existingId
    ? await drive.metadata(existingId)
    : (await drive.children(parent)).find((f) => f.name === name);
  const id = existing?.id ?? (await drive.empty(parent, name));
  if (
    existing?.md5Checksum !== checksum ||
    Number(existing?.size) !== bytes.length
  ) {
    const session = await drive.begin(id, bytes.length);
    for (let offset = 0; offset < bytes.length; offset += 256 * 1024) {
      await drive.chunk(
        session,
        bytes.subarray(offset, offset + 256 * 1024),
        offset,
        bytes.length,
      );
    }
  }
  const file = await drive.metadata(id);
  if (file.md5Checksum !== checksum || Number(file.size) !== bytes.length) {
    throw new ApiError(502, "SHARED_EXPORT_VERIFICATION_FAILED");
  }
  return artifact(file);
}

/** One bounded, retryable job. Invoke from the authenticated dispatcher or CLI.
 * Jobs survive process death; retries freeze a consistent snapshot; no network inside the map lock.
 */
export async function exportSharedMap(
  database: Database,
  drive: Drive,
  root: string,
): Promise<boolean> {
  const token = randomUUID();
  const job = await database.transaction(async (db) => {
    const { rows } =
      await db.query(`select j.* from firecheck_sync.export_jobs j
      join firecheck_sync.maps m using(assignment_id)
      where m.enabled and j.desired_revision>m.export_revision
      and j.next_attempt_at<=now() and (j.lease_until is null or j.lease_until<now())
      order by j.next_attempt_at for update of j skip locked limit 1`);
    if (!rows[0]) return null;
    await db.query(
      `update firecheck_sync.export_jobs set lease_token=$2,
      lease_until=now()+interval '3 minutes',attempts=attempts+1 where assignment_id=$1`,
      [rows[0].assignment_id, token],
    );
    return rows[0];
  });
  if (!job) return false;
  const aid = job.assignment_id;
  try {
    const snapshot = await database.transaction(async (db) => {
      // A single statement observes map revision and every projected feature at
      // one MVCC snapshot. Limits fail explicitly, never publish a truncated map.
      const { rows } = await db.query(
        `select case when (select count(*)<=10000
        and coalesce(sum(octet_length(payload::text)),0)<=16777216 from firecheck_sync.current_features
        where assignment_id=m.assignment_id) then jsonb_build_object('schema_version',1,
        'assignment_id',m.assignment_id,'revision',m.revision,
        'assignment',jsonb_build_object('id',a.id,'name',a.name,'campaign_id',a.campaign_id,
          'boundary',st_asgeojson(a.boundary_polygon::geometry)::jsonb),
        'features',coalesce((select jsonb_agg(c.payload order by c.feature_id)
          from firecheck_sync.current_features c where c.assignment_id=m.assignment_id),'[]'::jsonb)) else null end snapshot
        from firecheck_sync.maps m join public.assignments a on a.id=m.assignment_id
        where m.assignment_id=$1`,
        [aid],
      );
      if (!rows[0]?.snapshot)
        throw new ApiError(413, "SHARED_EXPORT_TOO_LARGE");
      const frozen = rows[0].snapshot as SharedSnapshot;
      const bytes = Buffer.byteLength(JSON.stringify(frozen));
      if (bytes > maxBytes || frozen.features.length > 10000)
        throw new ApiError(413, "SHARED_EXPORT_TOO_LARGE");
      return frozen;
    });
    const native = Buffer.from(JSON.stringify(snapshot));
    const gis = Buffer.from(JSON.stringify(geoJson(snapshot)));
    const map = await drive.managedFolder(
      root,
      String(snapshot.assignment.name ?? "Map"),
      `map:${aid}`,
    );
    const archive = await drive.managedFolder(
      map.id,
      "Archive",
      `archive:${aid}`,
    );
    const version = await drive.managedFolder(
      archive.id,
      `r${snapshot.revision}`,
      `shared:${aid}:${snapshot.revision}`,
    );
    const files = [
      await writeVerified(drive, version.id, "shared-map.json", native),
      await writeVerified(drive, version.id, "map.geojson", gis),
    ];
    // Serialize only export promotion. Normal record commits use a separate lock.
    await database.transaction(async (db) => {
      await db.query("select pg_advisory_xact_lock(hashtextextended($1,0))", [
        `shared-export:${aid}`,
      ]);
      const { rows } = await db.query(
        `select j.lease_token,j.lease_until,m.export_revision
        from firecheck_sync.export_jobs j join firecheck_sync.maps m using(assignment_id)
        where j.assignment_id=$1`,
        [aid],
      );
      if (
        rows[0]?.lease_token !== token ||
        new Date(rows[0].lease_until) <= new Date()
      )
        throw new Error("Export lease lost");
      if (Number(rows[0].export_revision) > snapshot.revision)
        throw new Error("Export superseded");
      // Retire registered contributor outputs without deleting or rewriting them.
      const { rows: legacy } = await db.query(
        `select id,folder_id,folder_path from firecheck_gateway.uploads
        where assignment_id=$1 and complete=true`,
        [aid],
      );
      for (const old of legacy) {
        const folder = await drive.metadata(old.folder_id);
        if (folder.parents?.includes(map.id)) {
          const name = `Legacy - ${folder.name} - ${old.id.slice(0, 8)}`;
          await drive.relocate(folder.id, archive.id, name);
          await db.query(
            "update firecheck_gateway.uploads set folder_path=$2 where id=$1",
            [old.id, `firecheck/output/${map.name}/Archive/${name}/`],
          );
        }
      }
      // A single resumable file replacement is visible only after completion.
      await writeVerified(drive, map.id, "Current.geojson", gis);
      const manifest = {
        revision: snapshot.revision,
        folderId: version.id,
        files,
      };
      await db.query(
        `insert into firecheck_sync.exports values($1,$2,$3,now())
        on conflict(assignment_id,revision) do update set manifest=excluded.manifest`,
        [aid, snapshot.revision, JSON.stringify(manifest)],
      );
      const { rows: prior } = await db.query(
        `select v.manifest from firecheck_gateway.sources s
        join firecheck_gateway.versions v on v.id=s.current_version where s.assignment_id=$1`,
        [aid],
      );
      const sidecars = (prior[0]?.manifest ?? []).filter((f: any) =>
        ["form_definition.json", "field_requirements.txt"].includes(f.name),
      );
      const versionId = randomUUID();
      await db.query(
        `insert into firecheck_gateway.versions(id,assignment_id,manifest,manifest_hash,published_by)
        values($1,$2,$3,$4,null)`,
        [
          versionId,
          aid,
          JSON.stringify([files[0], ...sidecars]),
          createHash("sha256").update(native).digest("hex"),
        ],
      );
      await db.query(
        "update firecheck_gateway.sources set current_version=$2 where assignment_id=$1",
        [aid, versionId],
      );
      await db.query(
        "update firecheck_sync.maps set export_revision=$2 where assignment_id=$1",
        [aid, snapshot.revision],
      );
      await db.query(
        `update firecheck_sync.export_jobs set lease_until=null,lease_token=null,last_error=null,attempts=0
        where assignment_id=$1 and lease_token=$2`,
        [aid, token],
      );
    });
    return true;
  } catch (e) {
    await database.pool.query(
      `update firecheck_sync.export_jobs set lease_until=null,lease_token=null,
      last_error=$3,next_attempt_at=now()+interval '1 minute' where assignment_id=$1 and lease_token=$2`,
      [aid, token, e instanceof ApiError ? e.code : "EXPORT_FAILED"],
    );
    throw e;
  }
}
