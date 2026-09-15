import { createHash } from "node:crypto";
export class ApiError extends Error {
  constructor(
    public status: number,
    public code: string,
    message = code,
  ) {
    super(message);
  }
}
export function assert(
  value: unknown,
  status: number,
  code: string,
): asserts value {
  if (!value) throw new ApiError(status, code);
}
export function uuid(value: unknown): string {
  assert(
    typeof value === "string" &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        value,
      ),
    400,
    "INVALID_ID",
  );
  return value.toLowerCase();
}
export const CHUNK_SIZE = 8 * 1024 * 1024;
export const MAX_FILE_SIZE = 512 * 1024 * 1024;
export const MAX_BATCH_SIZE = 1024 * 1024 * 1024;
export function boundaryPolygon(value: unknown): string {
  const geometry = value as { type?: string; coordinates?: unknown };
  assert(
    geometry?.type === "Polygon" && Array.isArray(geometry.coordinates),
    400,
    "INVALID_BOUNDARY",
  );
  const rings = geometry.coordinates as unknown[][];
  assert(rings.length > 0 && rings.length <= 100, 400, "INVALID_BOUNDARY");
  let points = 0;
  for (const ring of rings) {
    assert(Array.isArray(ring) && ring.length >= 4, 400, "INVALID_BOUNDARY");
    points += ring.length;
    assert(points <= 10000, 400, "INVALID_BOUNDARY");
    for (const point of ring) {
      assert(
        Array.isArray(point) &&
          point.length === 2 &&
          point.every((n) => typeof n === "number" && Number.isFinite(n)),
        400,
        "INVALID_BOUNDARY",
      );
      assert(
        Math.abs(point[0]) <= 180 && Math.abs(point[1]) <= 90,
        400,
        "INVALID_BOUNDARY",
      );
    }
    assert(
      JSON.stringify(ring[0]) === JSON.stringify(ring.at(-1)),
      400,
      "INVALID_BOUNDARY",
    );
  }
  return JSON.stringify({ type: "Polygon", coordinates: rings });
}
export interface Artifact {
  id: string;
  name: string;
  size: number;
  md5: string;
  driveId: string;
}
export interface UploadSpec {
  id: string;
  name: string;
  size: number;
  md5: string;
}
export function uploadSpecs(value: unknown): UploadSpec[] {
  assert(
    Array.isArray(value) && value.length > 0 && value.length <= 100,
    400,
    "INVALID_MANIFEST",
  );
  const names = new Set<string>();
  const ids = new Set<string>();
  let total = 0;
  const result = value.map((v: any) => {
    assert(v && typeof v === "object", 400, "INVALID_MANIFEST");
    const id = uuid(v.id);
    assert(
      typeof v.name === "string" &&
        /^[a-zA-Z0-9][a-zA-Z0-9_. -]{0,159}\.(shp|shx|dbf|prj|json|txt|jpg|jpeg|png)$/i.test(
          v.name,
        ) &&
        !v.name.includes(".."),
      400,
      "INVALID_FILENAME",
    );
    assert(
      Number.isSafeInteger(v.size) && v.size > 0 && v.size <= MAX_FILE_SIZE,
      400,
      "INVALID_SIZE",
    );
    assert(
      typeof v.md5 === "string" && /^[a-f0-9]{32}$/.test(v.md5),
      400,
      "INVALID_CHECKSUM",
    );
    assert(
      !names.has(v.name.toLowerCase()) && !ids.has(id),
      400,
      "DUPLICATE_FILE",
    );
    names.add(v.name.toLowerCase());
    ids.add(id);
    total += v.size;
    return { id, name: v.name, size: v.size, md5: v.md5 };
  });
  assert(total <= MAX_BATCH_SIZE, 413, "BATCH_TOO_LARGE");
  return result.sort((a, b) => a.id.localeCompare(b.id));
}
export const hash = (value: unknown) =>
  createHash("sha256").update(JSON.stringify(value)).digest("hex");
export function validateMap(files: Artifact[]): void {
  assert(files.length > 0 && files.length <= 100, 400, "INVALID_MAP");
  let total = 0;
  const names = new Set<string>();
  const groups = new Map<string, Set<string>>();
  for (const f of files) {
    assert(
      /^[a-zA-Z0-9][a-zA-Z0-9_. -]{0,159}$/.test(f.name) &&
        !f.name.includes(".."),
      400,
      "INVALID_FILENAME",
    );
    assert(!names.has(f.name.toLowerCase()), 400, "DUPLICATE_FILE");
    names.add(f.name.toLowerCase());
    assert(
      Number.isSafeInteger(f.size) &&
        f.size > 0 &&
        f.size <= MAX_FILE_SIZE &&
        /^[a-f0-9]{32}$/.test(f.md5),
      400,
      "INVALID_MAP_FILE",
    );
    total += f.size;
    const match = /^(.*)\.(shp|shx|dbf|prj)$/i.exec(f.name);
    if (match) {
      const base = match[1]!.toLowerCase();
      const set = groups.get(base) ?? new Set();
      set.add(match[2]!.toLowerCase());
      groups.set(base, set);
    }
  }
  assert(total <= MAX_BATCH_SIZE && groups.size > 0, 400, "INVALID_MAP");
  for (const set of groups.values())
    assert(
      ["shp", "shx", "dbf", "prj"].every((ext) => set.has(ext)),
      400,
      "INCOMPLETE_SHAPEFILE",
    );
}
