import { test } from "node:test";
import { strict as assert } from "node:assert";
import { GoogleDrive } from "../src/drive.js";
test("fresh marked folders issue one creation request without a parent listing", async () => {
  const original = globalThis.fetch;
  const requests: Array<{ url: string; body: any }> = [];
  globalThis.fetch = async (input, options) => {
    requests.push({
      url: String(input),
      body: JSON.parse(String(options?.body)),
    });
    return Response.json({ id: "fresh" });
  };
  try {
    const drive = new GoogleDrive(async () => "synthetic-test-token");
    assert.equal(
      await drive.folder("published", "new version", "source-publication:test"),
      "fresh",
    );
    assert.equal(requests.length, 1);
    assert.equal(
      requests[0]!.body.appProperties.firecheckOutputKey,
      "source-publication:test",
    );
    assert.deepEqual(requests[0]!.body.parents, ["published"]);
  } finally {
    globalThis.fetch = original;
  }
});
test("development inspection reads all permission pages and quota without mutations", async () => {
  const original = globalThis.fetch;
  const paths: URL[] = [];
  globalThis.fetch = async (input) => {
    const url = new URL(String(input));
    paths.push(url);
    if (url.pathname.endsWith("/about"))
      return Response.json({ storageQuota: { limit: "999", usage: "123" } });
    if (url.pathname.endsWith("/permissions"))
      return Response.json(
        url.searchParams.has("pageToken")
          ? { permissions: [{ type: "anyone", role: "reader" }] }
          : {
              permissions: [{ type: "user", role: "owner" }],
              nextPageToken: "next",
            },
      );
    return Response.json({ id: "sandbox", ownedByMe: true });
  };
  try {
    const drive = new GoogleDrive(async () => "synthetic-test-token");
    assert.deepEqual(await drive.storageQuota(), {
      limit: "999",
      usage: "123",
    });
    const access = await drive.folderAccess("sandbox");
    assert.equal(access.ownedByMe, true);
    assert.equal(access.permissions.length, 2);
    assert.ok(paths.every((url) => url.hostname === "www.googleapis.com"));
  } finally {
    globalThis.fetch = original;
  }
});
