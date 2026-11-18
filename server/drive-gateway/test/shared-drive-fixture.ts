import { randomUUID, createHash } from "node:crypto";
import type { Drive, DriveFile } from "../src/drive.js";
export class SharedTestDrive implements Drive {
  files = new Map<string, DriveFile>();
  bytes = new Map<string, Buffer>();
  fail = false;
  sessions = new Map<string, { id: string; size: number; bytes: Buffer }>();
  async metadata(id: string) {
    const f = this.files.get(id);
    if (!f) throw new Error("missing");
    return { ...f };
  }
  async children(parent: string) {
    return [...this.files.values()].filter((f) => f.parents?.includes(parent));
  }
  async folder(parent: string, name: string) {
    const id = randomUUID();
    this.files.set(id, {
      id,
      name,
      mimeType: "application/vnd.google-apps.folder",
      parents: [parent],
    });
    return id;
  }
  async managedFolder(parent: string, name: string, key: string) {
    let f = (await this.children(parent)).find(
      (f) => f.appProperties?.firecheckOutputKey === key,
    );
    if (!f) {
      const id = await this.folder(parent, name);
      f = this.files.get(id)!;
      f.appProperties = { firecheckOutputKey: key };
    }
    return { ...f };
  }
  async relocate(id: string, parent: string, name: string) {
    Object.assign(this.files.get(id)!, { parents: [parent], name });
  }
  async copy(id: string, parent: string) {
    const f = await this.metadata(id);
    const other = await this.empty(parent, f.name);
    this.set(other, this.bytes.get(id)!);
    return this.metadata(other);
  }
  set(id: string, bytes: Buffer) {
    this.bytes.set(id, bytes);
    Object.assign(this.files.get(id)!, {
      size: String(bytes.length),
      md5Checksum: createHash("md5").update(bytes).digest("hex"),
    });
  }
  async empty(parent: string, name: string) {
    const id = randomUUID();
    this.files.set(id, {
      id,
      name,
      mimeType: "application/octet-stream",
      parents: [parent],
    });
    this.set(id, Buffer.alloc(0));
    return id;
  }
  async stream(id: string) {
    return new Response(new Uint8Array(this.bytes.get(id)!));
  }
  async begin(id: string, size: number) {
    if (this.fail) throw new Error("Drive unavailable");
    const key = randomUUID();
    this.sessions.set(key, { id, size, bytes: Buffer.alloc(0) });
    return key;
  }
  async status(key: string) {
    const s = this.sessions.get(key)!;
    return {
      offset: s.bytes.length,
      complete: s.bytes.length === s.size,
      expired: false,
    };
  }
  async chunk(key: string, bytes: Buffer, offset: number, size: number) {
    const s = this.sessions.get(key)!;
    if (s.bytes.length !== offset) throw new Error("offset");
    s.bytes = Buffer.concat([s.bytes, bytes]);
    if (s.bytes.length === size) this.set(s.id, s.bytes);
  }
}
