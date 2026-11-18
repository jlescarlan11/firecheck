import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { releaseInfo, uploadVerified } from "../tools/publish-apk.js";
import type { Drive } from "../src/drive.js";

test("release gate rejects another package or unsupported ABI", () => {
  const valid =
    "package: name='ph.gov.bfp.firecheck' versionCode='4013' versionName='0.1.9'\nnative-code: 'arm64-v8a'\n";
  assert.deepEqual(releaseInfo(valid), { code: 4013, version: "0.1.9" });
  assert.throws(() =>
    releaseInfo(valid.replace("ph.gov.bfp.firecheck", "another.app")),
  );
  assert.throws(() => releaseInfo(valid.replace("arm64-v8a", "x86_64")));
});

test("already uploaded identical APK is not uploaded again", async () => {
  const bytes = Buffer.from("apk");
  const md5Checksum = createHash("md5").update(bytes).digest("hex");
  await uploadVerified(
    {
      metadata: async () => ({ md5Checksum, size: "3" }),
      begin: () => {
        throw new Error("unexpected upload");
      },
    } as unknown as Drive,
    "file",
    bytes,
  );
});

test("lost chunk acknowledgement resumes from server offset and verifies hash", async () => {
  const bytes = Buffer.from("apk");
  let uploaded = false;
  const md5 = createHash("md5").update(bytes).digest("hex");
  const drive = {
    metadata: async () => (uploaded ? { md5Checksum: md5, size: "3" } : {}),
    begin: async () => "session",
    chunk: async () => {
      uploaded = true;
      throw new Error("lost acknowledgement");
    },
    status: async () => ({ offset: 3, complete: true, expired: false }),
  } as unknown as Drive;
  await uploadVerified(drive, "file", bytes);
});

test("does not accept corrupt remote content", async () => {
  const drive = {
    metadata: async () => ({ md5Checksum: "wrong", size: "3" }),
    begin: async () => "session",
    chunk: async () => {},
  } as unknown as Drive;
  await assert.rejects(
    uploadVerified(drive, "file", Buffer.from("apk")),
    /checksum/,
  );
});
