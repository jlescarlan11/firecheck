import { GoogleAuth, Impersonated, OAuth2Client } from "google-auth-library";
import { Readable } from "node:stream";
import { ApiError, assert, type Artifact } from "./domain.js";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import process from "node:process";
export interface DriveFile {
  id: string;
  name: string;
  mimeType: string;
  size?: string;
  md5Checksum?: string;
  parents?: string[];
  driveId?: string;
  trashed?: boolean;
  appProperties?: Record<string, string>;
}
export interface Drive {
  metadata(id: string): Promise<DriveFile>;
  children(id: string): Promise<DriveFile[]>;
  folder(parent: string, name: string, key?: string): Promise<string>;
  managedFolder(parent: string, name: string, key: string): Promise<DriveFile>;
  relocate(id: string, parent: string, name: string): Promise<void>;
  copy(id: string, parent: string): Promise<DriveFile>;
  empty(parent: string, name: string): Promise<string>;
  stream(id: string, range?: string): Promise<Response>;
  begin(id: string, size: number): Promise<string>;
  status(
    url: string,
    size: number,
  ): Promise<{ offset: number; complete: boolean; expired: boolean }>;
  chunk(
    url: string,
    bytes: Buffer,
    offset: number,
    size: number,
  ): Promise<void>;
}
export class GoogleDrive implements Drive {
  constructor(private token: () => Promise<string>) {}
  private async request(path: string, init: RequestInit = {}) {
    const url = path.startsWith("https:")
      ? new URL(path)
      : new URL(path, "https://www.googleapis.com");
    assert(
      url.origin === "https://www.googleapis.com" &&
        (url.pathname.startsWith("/drive/v3/") ||
          url.pathname.startsWith("/upload/drive/v3/")),
      500,
      "INVALID_UPSTREAM_URL",
    );
    const response = await fetch(url, {
      ...init,
      redirect: "manual",
      signal: AbortSignal.timeout(60000),
      headers: {
        ...init.headers,
        Authorization: `Bearer ${await this.token()}`,
      },
    });
    if ([401, 403].includes(response.status)) {
      await response.body?.cancel();
      throw new ApiError(503, "DRIVE_CONNECTION_UNAVAILABLE");
    }
    if (response.status === 429 || response.status >= 500) {
      await response.body?.cancel();
      throw new ApiError(503, "DRIVE_TEMPORARILY_UNAVAILABLE");
    }
    return response;
  }
  private async json(path: string, init?: RequestInit): Promise<any> {
    const r = await this.request(path, init);
    if (!r.ok) {
      await r.body?.cancel();
      throw new ApiError(502, "DRIVE_REQUEST_FAILED");
    }
    return r.json();
  }
  /** Read-only development diagnostics; never changes account or file permissions. */
  async storageQuota(): Promise<{ limit?: string; usage: string }> {
    return (await this.json("/drive/v3/about?fields=storageQuota"))
      .storageQuota;
  }
  async folderAccess(
    id: string,
  ): Promise<{
    ownedByMe: boolean;
    permissions: Array<{ type: string; role: string; deleted?: boolean }>;
  }> {
    const file = await this.json(
      `/drive/v3/files/${encodeURIComponent(id)}?supportsAllDrives=true&fields=ownedByMe`,
    );
    const permissions = [];
    let pageToken: string | undefined;
    do {
      const query = new URLSearchParams({
        supportsAllDrives: "true",
        pageSize: "100",
        fields: "nextPageToken,permissions(type,role,deleted)",
      });
      if (pageToken) query.set("pageToken", pageToken);
      const page = await this.json(
        `/drive/v3/files/${encodeURIComponent(id)}/permissions?${query}`,
      );
      permissions.push(...page.permissions);
      pageToken = page.nextPageToken;
      assert(permissions.length <= 1000, 413, "TOO_MANY_PERMISSIONS");
    } while (pageToken);
    return { ownedByMe: file.ownedByMe, permissions };
  }
  metadata(id: string): Promise<DriveFile> {
    return this.json(
      `/drive/v3/files/${encodeURIComponent(id)}?supportsAllDrives=true&fields=id,name,mimeType,size,md5Checksum,parents,driveId,trashed,appProperties`,
    );
  }
  async children(id: string) {
    const result: DriveFile[] = [];
    let pageToken: string | undefined;
    do {
      const q = new URLSearchParams({
        q: `'${id.replaceAll("'", "\\'")}' in parents and trashed = false`,
        supportsAllDrives: "true",
        includeItemsFromAllDrives: "true",
        pageSize: "100",
        fields:
          "nextPageToken,files(id,name,mimeType,size,md5Checksum,parents,driveId,trashed,appProperties)",
      });
      if (pageToken) q.set("pageToken", pageToken);
      const data = await this.json(`/drive/v3/files?${q}`);
      result.push(...data.files);
      pageToken = data.nextPageToken;
      assert(result.length <= 1000, 413, "TOO_MANY_FILES");
    } while (pageToken);
    return result;
  }
  async folder(parent: string, name: string, key?: string) {
    const result = await this.json(
      "/drive/v3/files?supportsAllDrives=true&fields=id",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name,
          ...(key ? { appProperties: { firecheckOutputKey: key } } : {}),
          parents: [parent],
          mimeType: "application/vnd.google-apps.folder",
        }),
      },
    );
    return result.id;
  }
  async managedFolder(parent: string, name: string, key: string) {
    const children = await this.children(parent);
    const existing = children.find(
      (f) => f.appProperties?.firecheckOutputKey === key,
    );
    if (existing) return existing;
    const label = children.some((f) => f.name === name)
      ? `${name} (${key.slice(-8)})`
      : name;
    return this.json(
      "/drive/v3/files?supportsAllDrives=true&fields=id,name,mimeType,parents,appProperties",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: label,
          parents: [parent],
          mimeType: "application/vnd.google-apps.folder",
          appProperties: { firecheckOutputKey: key },
        }),
      },
    ) as Promise<DriveFile>;
  }
  async relocate(id: string, parent: string, name: string) {
    const current = await this.metadata(id);
    const query = new URLSearchParams({
      supportsAllDrives: "true",
      fields: "id",
    });
    if (!current.parents?.includes(parent)) {
      query.set("addParents", parent);
      if (current.parents?.length)
        query.set("removeParents", current.parents.join(","));
    }
    await this.json(`/drive/v3/files/${encodeURIComponent(id)}?${query}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name }),
    });
  }
  copy(id: string, parent: string): Promise<DriveFile> {
    return this.json(
      `/drive/v3/files/${encodeURIComponent(id)}/copy?supportsAllDrives=true&fields=id,name,mimeType,size,md5Checksum`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ parents: [parent] }),
      },
    );
  }
  async empty(parent: string, name: string) {
    const result = await this.json(
      "/drive/v3/files?supportsAllDrives=true&fields=id",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name,
          parents: [parent],
          mimeType: "application/octet-stream",
        }),
      },
    );
    return result.id;
  }
  async stream(id: string, range?: string) {
    const r = await this.request(
      `/drive/v3/files/${encodeURIComponent(id)}?alt=media&supportsAllDrives=true`,
      { headers: range ? { Range: range } : {} },
    );
    if (!r.ok) {
      await r.body?.cancel();
      throw new ApiError(r.status === 416 ? 416 : 502, "DOWNLOAD_FAILED");
    }
    return r;
  }
  async begin(id: string, size: number) {
    const r = await this.request(
      `/upload/drive/v3/files/${encodeURIComponent(id)}?uploadType=resumable&supportsAllDrives=true`,
      {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-Upload-Content-Type": "application/octet-stream",
          "X-Upload-Content-Length": String(size),
        },
        body: "{}",
      },
    );
    assert(r.ok && r.headers.get("location"), 502, "UPLOAD_SESSION_FAILED");
    await r.body?.cancel();
    return r.headers.get("location")!;
  }
  async status(url: string, size: number) {
    const r = await this.request(url, {
      method: "PUT",
      headers: { "Content-Length": "0", "Content-Range": `bytes */${size}` },
    });
    const range = r.headers.get("range");
    await r.body?.cancel();
    if (r.status === 404 || r.status === 410)
      return { offset: 0, complete: false, expired: true };
    if (r.status === 200 || r.status === 201)
      return { offset: size, complete: true, expired: false };
    assert(r.status === 308, 502, "UPLOAD_STATUS_FAILED");
    return {
      offset: range ? Number(range.split("-")[1]) + 1 : 0,
      complete: false,
      expired: false,
    };
  }
  async chunk(url: string, bytes: Buffer, offset: number, size: number) {
    const r = await this.request(url, {
      method: "PUT",
      headers: {
        "Content-Type": "application/octet-stream",
        "Content-Length": String(bytes.length),
        "Content-Range": `bytes ${offset}-${offset + bytes.length - 1}/${size}`,
      },
      body: new Uint8Array(bytes),
    });
    await r.body?.cancel();
    assert([200, 201, 308].includes(r.status), 502, "UPLOAD_CHUNK_FAILED");
  }
}
export async function driveFromEnvironment(
  env: Record<string, string | undefined> = process.env,
) {
  const mode = env.DRIVE_AUTH_MODE ?? "oauth";
  assert(
    ["oauth", "service_account"].includes(mode),
    500,
    "INVALID_DRIVE_AUTH_MODE",
  );
  if (mode === "oauth") {
    const credentials = env.GOOGLE_OAUTH_BUNDLE_FILE
      ? JSON.parse(await readFile(env.GOOGLE_OAUTH_BUNDLE_FILE, "utf8"))
      : env;
    const client = new OAuth2Client(
      credentials.GOOGLE_CLIENT_ID,
      credentials.GOOGLE_CLIENT_SECRET,
    );
    assert(
      credentials.GOOGLE_REFRESH_TOKEN &&
        credentials.GOOGLE_CLIENT_ID &&
        credentials.GOOGLE_CLIENT_SECRET,
      500,
      "MISSING_SERVER_OAUTH_CONFIGURATION",
    );
    client.setCredentials({ refresh_token: credentials.GOOGLE_REFRESH_TOKEN });
    return new GoogleDrive(async () => {
      try {
        const r = await client.getAccessToken();
        assert(r.token, 503, "DRIVE_CONNECTION_UNAVAILABLE");
        return r.token;
      } catch {
        throw new ApiError(503, "DRIVE_CONNECTION_UNAVAILABLE");
      }
    });
  }
  assert(
    env.DRIVE_SERVICE_ACCOUNT && env.SHARED_DRIVE_ID,
    500,
    "MISSING_SERVICE_ACCOUNT_CONFIGURATION",
  );
  const source = await new GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/cloud-platform"],
  }).getClient();
  const client = new Impersonated({
    sourceClient: source,
    targetPrincipal: env.DRIVE_SERVICE_ACCOUNT,
    targetScopes: ["https://www.googleapis.com/auth/drive"],
    lifetime: 3600,
  });
  return new GoogleDrive(async () => {
    const r = await client.getAccessToken();
    assert(r.token, 503, "DRIVE_CONNECTION_UNAVAILABLE");
    return r.token;
  });
}
export async function descendant(
  drive: Drive,
  id: string,
  root: string,
  sharedDrive?: string,
) {
  const seen = new Set<string>();
  let current = id;
  for (let i = 0; i < 32; i++) {
    assert(!seen.has(current), 400, "INVALID_DRIVE_FOLDER");
    seen.add(current);
    const f = await drive.metadata(current);
    assert(
      !f.trashed && f.mimeType === "application/vnd.google-apps.folder",
      400,
      "INVALID_DRIVE_FOLDER",
    );
    if (sharedDrive)
      assert(f.driveId === sharedDrive, 400, "WRONG_SHARED_DRIVE");
    if (current === root) return;
    assert(f.parents?.length === 1, 400, "FOLDER_OUTSIDE_INPUT_ROOT");
    current = f.parents[0]!;
  }
  throw new ApiError(400, "FOLDER_OUTSIDE_INPUT_ROOT");
}
export function artifact(f: DriveFile): Artifact {
  return {
    id: randomUUID(),
    name: f.name,
    size: Number(f.size),
    md5: f.md5Checksum ?? "",
    driveId: f.id,
  };
}
export const nodeStream = (response: Response) =>
  Readable.fromWeb(response.body as any);
