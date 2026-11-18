import { test } from "node:test";
import { strict as assert } from "node:assert";
import { inventoryPublications } from "../src/orphan-inventory.js";
import { SharedTestDrive } from "./shared-drive-fixture.js";
const folder = (id: string, key?: string) => ({
  id,
  name: "untrusted label",
  mimeType: "application/vnd.google-apps.folder",
  parents: ["published"],
  ...(key ? { appProperties: { firecheckOutputKey: key } } : {}),
});
const assignment = "00000000-0000-0000-0000-000000000001";
const version = "00000000-0000-0000-0000-000000000002";
const key = `source-publication:${assignment}:${version}`;
const references = {
  roots: ["published", "input", "output"],
  folderIds: ["active-upload", "archive", "export"],
  fileIds: ["retained-file"],
  versionIds: [version],
};
test("inventory protects every retained version, upload, archive, export, configured root and unknown folder", async () => {
  const drive = new SharedTestDrive();
  for (const id of [
    "active-upload",
    "archive",
    "export",
    "input",
    "unknown",
    "historical",
    "old-version",
  ])
    drive.files.set(id, folder(id, id === "old-version" ? key : undefined));
  drive.files.set(
    "historical",
    folder(
      "historical",
      `source-publication:${assignment}:00000000-0000-0000-0000-000000000003`,
    ),
  );
  drive.files.set("retained-file", {
    id: "retained-file",
    name: "map.shp",
    mimeType: "application/octet-stream",
    parents: ["historical"],
  });
  const report = await inventoryPublications(drive, "published", async () =>
    structuredClone(references),
  );
  assert.equal(report.status, "complete");
  assert.equal(report.entries.length, 7);
  assert.ok(report.entries.every((e) => e.classification === "protected"));
  assert.equal(
    report.entries.find((e) => e.folderId === "unknown")!.reason,
    "unknown-provenance",
  );
  assert.equal(
    report.entries.find((e) => e.folderId === "historical")!.reason,
    "retained-reference",
  );
  assert.deepEqual(
    report.entries.map((e) => e.folderId),
    report.entries.map((e) => e.folderId).sort(),
  );
});
test("uncommitted preparing publications are review-only, with no safe-delete assertion or age inference", async () => {
  const drive = new SharedTestDrive();
  drive.files.set(
    "preparing",
    folder(
      "preparing",
      `source-publication:${assignment}:00000000-0000-0000-0000-000000000003`,
    ),
  );
  const report = await inventoryPublications(drive, "published", async () => ({
    roots: ["published"],
    folderIds: [],
    fileIds: [],
    versionIds: [],
  }));
  assert.equal(report.status, "inconclusive");
  assert.deepEqual(report.entries, [
    {
      folderId: "preparing",
      classification: "review-only",
      reason: "possibly-in-flight-publication",
    },
  ]);
});
test("changed references and listing overflow cannot yield partial orphan classifications", async () => {
  const drive = new SharedTestDrive();
  drive.files.set("preparing", folder("preparing", key));
  let reads = 0;
  const report = await inventoryPublications(drive, "published", async () => ({
    roots: ["published"],
    folderIds: reads++ ? ["preparing"] : [],
    fileIds: [],
    versionIds: [],
  }));
  assert.equal(report.status, "inconclusive");
  assert.equal(report.reason, "references-changed");
  assert.deepEqual(report.entries, []);
  drive.children = async () => {
    throw new Error("TOO_MANY_FILES");
  };
  const overflow = await inventoryPublications(
    drive,
    "published",
    async () => references,
  );
  assert.equal(overflow.status, "inconclusive");
  assert.equal(overflow.reason, "inspection-failed");
  assert.deepEqual(overflow.entries, []);
});
