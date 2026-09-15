/** Writes only a newly created probe folder. Leaves it for supervisor review. */
import { createHash, randomUUID } from "node:crypto";
import { driveFromEnvironment, descendant } from "../src/drive.js";
const drive = await driveFromEnvironment();
const input = process.env.DRIVE_INPUT_ROOT,
  output = process.env.DRIVE_OUTPUT_ROOT;
if (!input || !output)
  throw new Error("Set DRIVE_INPUT_ROOT and DRIVE_OUTPUT_ROOT.");
await descendant(drive, input, input, process.env.SHARED_DRIVE_ID);
await descendant(drive, output, output, process.env.SHARED_DRIVE_ID);
const inputChildren = await drive.children(input);
const folder = await drive.folder(
  output,
  `firecheck-gateway-probe-${randomUUID()}`,
);
const file = await drive.empty(folder, "resume-check.bin");
const data = Buffer.alloc(256 * 1024 + 64, 23);
const session = await drive.begin(file, data.length);
await drive.chunk(session, data.subarray(0, 256 * 1024), 0, data.length);
const status = await drive.status(session, data.length);
if (status.offset !== 256 * 1024 || status.complete)
  throw new Error("Resume probe returned an unexpected offset.");
await drive.chunk(
  session,
  data.subarray(status.offset),
  status.offset,
  data.length,
);
const meta = await drive.metadata(file);
if (meta.md5Checksum !== createHash("md5").update(data).digest("hex"))
  throw new Error("Probe checksum mismatch.");
const downloaded = Buffer.from(
  await (await drive.stream(file, "bytes=262144-")).arrayBuffer(),
);
if (!downloaded.equals(data.subarray(262144)))
  throw new Error("Range download mismatch.");
console.log(
  JSON.stringify({
    ok: true,
    inputFolderCount: inputChildren.length,
    probeFolderId: folder,
    probeFileId: file,
    checks: [
      "folder-access",
      "file-create",
      "resumable-upload",
      "checksum",
      "range-download",
    ],
  }),
);
